"""Strands agent served by AgentCore Runtime.

Strands calls Bedrock and runs tools; AgentCore hosts requests and provides
the optional memory and browser resources configured by Terraform.
"""

import os
import json
import logging
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from botocore.utils import ArnParser
from strands import Agent, tool
from strands_tools import calculator
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from bedrock_agentcore.memory.integrations.strands.config import (
    AgentCoreMemoryConfig,
    RetrievalConfig,
)
from bedrock_agentcore.memory.integrations.strands.session_manager import (
    AgentCoreMemorySessionManager,
)
from strands.models import BedrockModel

# Send application and tool logs to the runtime's standard log stream.
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('bedrock-agent-runtime')

# Terraform passes resource maps as JSON strings (see runtime.tf).
# Missing maps default to empty dictionaries so integrations stay optional.
try:
    runtimes = json.loads(os.environ.get("RUNTIMES", "{}"))
    memories = json.loads(os.environ.get("MEMORIES", "{}"))
    gateways = json.loads(os.environ.get("GATEWAYS", "{}"))
    browsers = json.loads(os.environ.get("BROWSERS", "{}"))
except json.JSONDecodeError as e:
    logger.error(f"Error parsing JSON from environment: {e}")
    runtimes = {}
    memories = {}
    gateways = {}
    browsers = {}

# Log logical names to help diagnose missing Terraform resource wiring.
logger.info("Available runtimes: %s", list(runtimes.keys()))
logger.info("Available memories: %s", list(memories.keys()))
logger.info("Available gateways: %s", list(gateways.keys()))
logger.info("Available browsers: %s", list(browsers.keys()))

# Terraform's logical names stay stable when AWS regenerates resource IDs.
# SDK calls below need bare IDs, which we extract from the supplied ARNs.
_arn_parser = ArnParser()


def _id_from_arn(arn):
    """Extract the bare resource ID from an AWS ARN.

    Uses botocore's ArnParser for ARN-shape validation, then takes the last
    segment of the resource portion. Handles all three resource-section
    forms: "TYPE/ID" (AgentCore, IAM), "TYPE:ID" (Logs, SNS, SQS), and
    bare "ID" (S3). Returns None for non-ARN input.
    """
    if not arn or not ArnParser.is_arn(arn):
        return None
    resource = _arn_parser.parse_arn(arn)["resource"]
    if "/" in resource:
        return resource.rsplit("/", 1)[-1] or None
    if ":" in resource:
        return resource.rsplit(":", 1)[-1] or None
    return resource or None

REGION = os.environ.get("AWS_REGION", "us-east-1")
# Namespace the semantic strategy writes to (see memory.tf). The session manager
# substitutes {actorId} at runtime and uses this as the retrieval namespace.
MEMORY_NAMESPACE = "/facts/{actorId}/"

MEMORY_ARN  = memories.get("semantic_memory", {}).get("arn")
BROWSER_ARN = browsers.get("web_browser", {}).get("arn")
MEMORY_ID   = _id_from_arn(MEMORY_ARN)
BROWSER_ID  = _id_from_arn(BROWSER_ARN)
if MEMORY_ID:
    logger.info("Memory enabled: %s (from %s)", MEMORY_ID, MEMORY_ARN)
else:
    logger.info("No memory configured; running stateless")
if BROWSER_ID:
    logger.info("Browse tool enabled: %s (from %s)", BROWSER_ID, BROWSER_ARN)
else:
    logger.info("No browser configured; browse tool disabled")

# The SDK serves runtime requests and dispatches them to @app.entrypoint.
app = BedrockAgentCoreApp()

# @tool exposes a function's signature and docstring to the model.


@tool
def weather(location: str = "Seattle, WA") -> str:
    """Get the current weather for a city, region, or postal address.

    Uses the public Open-Meteo geocoder and forecast API. No API key is
    required. Pass a specific location when the user asks about somewhere
    other than the default city.
    """
    location = (location or "Seattle, WA").strip()
    logger.info("Weather tool called for location=%s", location)

    def get_json(url: str) -> dict:
        request = Request(url, headers={"User-Agent": "bedrock-agent-core/1.0"})
        # Time out stalled network operations so a weather lookup can fail promptly.
        with urlopen(request, timeout=10) as response:
            return json.load(response)

    try:
        # Resolve the location to coordinates before requesting current conditions.
        geocode_url = "https://geocoding-api.open-meteo.com/v1/search?" + urlencode({
            "name": location,
            "count": 1,
            "language": "en",
            "format": "json",
        })
        places = get_json(geocode_url).get("results") or []
        if not places:
            return f"I couldn't find a location matching {location!r}."

        place = places[0]
        forecast_url = "https://api.open-meteo.com/v1/forecast?" + urlencode({
            "latitude": place["latitude"],
            "longitude": place["longitude"],
            "current": (
                "temperature_2m,apparent_temperature,relative_humidity_2m,"
                "weather_code,wind_speed_10m"
            ),
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "timezone": "auto",
        })
        current = get_json(forecast_url).get("current") or {}
        weather_code = current.get("weather_code")
        # Translate the API's numeric weather codes into readable tool output.
        conditions = {
            0: "clear sky",
            1: "mainly clear",
            2: "partly cloudy",
            3: "overcast",
            45: "foggy",
            48: "depositing rime fog",
            51: "light drizzle",
            53: "drizzle",
            55: "heavy drizzle",
            61: "light rain",
            63: "rain",
            65: "heavy rain",
            71: "light snow",
            73: "snow",
            75: "heavy snow",
            80: "light rain showers",
            81: "rain showers",
            82: "heavy rain showers",
            95: "thunderstorms",
            96: "thunderstorms with hail",
            99: "thunderstorms with heavy hail",
        }
        place_name = ", ".join(
            value for value in (place.get("name"), place.get("admin1"), place.get("country"))
            if value
        )
        return (
            f"Current weather in {place_name}: {conditions.get(weather_code, 'unknown conditions')}, "
            f"{current.get('temperature_2m')}°F (feels like {current.get('apparent_temperature')}°F), "
            f"humidity {current.get('relative_humidity_2m')}%, "
            f"wind {current.get('wind_speed_10m')} mph."
        )
    except (HTTPError, URLError, TimeoutError, KeyError, ValueError) as exc:
        # Return a failed lookup as tool output so the agent can explain it.
        logger.warning("Weather lookup failed for %s: %s", location, exc)
        return f"I couldn't retrieve weather for {location!r} right now."

# This local tool returns text without an external service call.


@tool
def greeting(name: str = "there"):
    """Generate a personalized greeting when the user introduces themselves.

    Call this tool when the user provides their name or asks for a greeting.

    Args:
        name: The user's name as provided, or "there" if no name is available.
    """
    logger.info(f"Greeting tool called with name: {name}")
    return f"Hello, {name}! Welcome to the Bedrock Agent Runtime."


@tool
def browse(url: str) -> str:
    """Open a URL in a managed browser session and return the visible page text.

    Use this when the user asks to read, summarize, or extract information
    from a specific web page. The browser is sandboxed and managed by
    AgentCore; this function starts a session, navigates, grabs text, and
    stops the session.
    """
    if not BROWSER_ID:
        return "Browser is not configured for this runtime."

    # Load browser dependencies only when this tool is invoked.
    from bedrock_agentcore.tools.browser_client import BrowserClient
    from playwright.sync_api import sync_playwright

    logger.info("Browse tool called with url=%s", url)
    region = os.environ.get("AWS_REGION", "us-east-1")
    # Manage the remote browser's lifetime explicitly, including failure cleanup.
    client = BrowserClient(region=region)
    session_started = False
    try:
        logger.info("browse: BrowserClient created; calling start(identifier=%s)", BROWSER_ID)
        start_resp = client.start(identifier=BROWSER_ID)
        session_started = True
        logger.info("browse: start returned: %r", start_resp)
        # Connect Playwright to the managed browser over Chrome DevTools Protocol.
        ws_url, headers = client.generate_ws_headers()
        logger.info("browse: ws_url=%s headers_keys=%s",
                    ws_url, list(headers.keys()) if headers else None)
        with sync_playwright() as pw:
            logger.info("browse: connecting over CDP")
            chromium = pw.chromium.connect_over_cdp(ws_url, headers=headers)
            logger.info("browse: CDP connected; contexts=%d", len(chromium.contexts))
            ctx = chromium.contexts[0] if chromium.contexts else chromium.new_context()
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            logger.info("browse: navigating to %s", url)
            resp = page.goto(url, wait_until="domcontentloaded", timeout=30000)
            logger.info("browse: goto returned status=%s final_url=%s title=%r",
                        resp.status if resp else None, page.url, page.title())
            text = page.inner_text("body")
            logger.info("browse: extracted %d chars; first 300=%r", len(text), text[:300])
            chromium.close()
            # Limit page text sent back to the model to keep tool output bounded.
            result = text[:4000]
            logger.info("browse: returning %d chars to agent", len(result))
            return result
    except Exception as e:
        logger.exception("Browse tool failed for url=%s", url)
        return f"Browse failed: {type(e).__name__}: {e}"
    finally:
        # Stop any started remote session, including after navigation errors.
        if session_started:
            try:
                client.stop()
                logger.info("browse: BrowserClient session stopped")
            except Exception:
                logger.exception("browse: error stopping BrowserClient session")


# Pass inference settings directly to BedrockModel, not additional_request_fields.
# An explicit output limit avoids reserving the model's larger default token budget.
model_id = os.environ.get("MODEL_ID", "global.anthropic.claude-sonnet-4-5-20250929-v1:0")
model = BedrockModel(
    model_id=model_id,
    temperature=0.1,  # Lower temperature for more consistent results
    max_tokens=2048,
)

# Tool registration makes tools available; this prompt guides when to call them.
# The memory session manager adds remembered facts to context separately.
BASE_SYSTEM_PROMPT = (
    "You're a helpful assistant. You can do simple math calculations, tell the weather, "
    "provide personalized greetings, and browse web pages. "
    "When the user introduces themselves or provides their name, call the greeting tool "
    "with that name before responding. Use the tool's greeting in your response, then "
    "acknowledge any other information they shared."
)

# calculator comes from strands_tools; the other tools are defined above.
# Strands executes the model's tool requests and feeds their results back to it.
TOOLS = [calculator, weather, greeting, browse]


def _build_agent(session_manager=None):
    """Construct the Strands agent, optionally wired to AgentCore Memory."""
    # Create an agent per invocation; session history belongs in the session manager.
    return Agent(
        model=model,
        tools=TOOLS,
        system_prompt=BASE_SYSTEM_PROMPT,
        session_manager=session_manager,
    )


@app.entrypoint
def bedrock_agent_runtime(payload, context):
    """Handle one prompt, with optional conversation history and user facts.

    payload["actor_id"] groups a user's memory across conversations. It is supplied
    by the caller, not derived from IAM; omitting it shares "default-user" memory.
    context.session_id identifies this conversation, including in the playground.
    The session manager recalls relevant facts and persists the turn's messages.
    """
    logger.info("Received payload: %s", json.dumps(payload))
    user_input = payload.get("prompt", "")
    actor_id   = payload.get("actor_id", "default-user")
    session_id = getattr(context, "session_id", None) or str(uuid.uuid4())
    logger.info("User input: %s (actor=%s, session=%s)", user_input, actor_id, session_id)

    # Without memory, each request starts fresh. str(result) extracts final text
    # without assuming the first response block contains text rather than tool use.
    if not MEMORY_ID:
        return str(_build_agent()(user_input))

    config = AgentCoreMemoryConfig(
        memory_id=MEMORY_ID,
        session_id=session_id,
        actor_id=actor_id,
        retrieval_config={
            # Retrieve up to five facts that meet the relevance threshold.
            MEMORY_NAMESPACE: RetrievalConfig(top_k=5, relevance_score=0.3),
        },
    )
    # Context manager flushes any buffered events when the turn completes.
    with AgentCoreMemorySessionManager(config, region_name=REGION) as session_manager:
        agent = _build_agent(session_manager=session_manager)
        text_response = str(agent(user_input))

    logger.info("Returning response: %s", text_response)
    return text_response


if __name__ == "__main__":
    # Start the SDK's HTTP server when launched by the container entry point.
    logger.info("Starting Bedrock Agent Runtime with STRANDS framework")
    app.run()
