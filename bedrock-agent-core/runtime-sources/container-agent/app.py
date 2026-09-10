"""
AWS STRANDS Agent with BedrockAgentCoreApp
This agent uses the STRANDS framework with BedrockAgentCoreApp to provide mathematical calculation and weather assistance.
"""

import os
import json
import logging
import uuid
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

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('bedrock-agent-runtime')

# Parse JSON resources from environment
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

# Log loaded resources
logger.info("Available runtimes: %s", list(runtimes.keys()))
logger.info("Available memories: %s", list(memories.keys()))
logger.info("Available gateways: %s", list(gateways.keys()))
logger.info("Available browsers: %s", list(browsers.keys()))

# Resolve ARNs by stable logical name (the key in var.memories /
# var.browsers). The "-XYZ" suffix on the AWS-assigned ID changes per
# deploy; the logical key does not. Bare resource IDs (needed by some SDK
# calls) are derived from the ARN at startup.
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

# Initialize the BedrockAgentCoreApp
app = BedrockAgentCoreApp()

# Create a custom weather tool


@tool
def weather():
    """Get weather information"""
    # Dummy implementation - in production, this would call a weather API
    logger.info("Weather tool called")
    return "It's sunny with a temperature of 72°F (22°C). Perfect weather for outdoor activities!"

# Create a custom greeting tool


@tool
def greeting(name: str = "there"):
    """Generate a personalized greeting"""
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

    # Imports kept local so module import doesn't cost the playwright load
    # when the tool isn't used.
    from bedrock_agentcore.tools.browser_client import BrowserClient
    from playwright.sync_api import sync_playwright

    logger.info("Browse tool called with url=%s", url)
    region = os.environ.get("AWS_REGION", "us-east-1")
    # BrowserClient in this SDK version is not a context manager — manage
    # session lifecycle explicitly with try/finally.
    client = BrowserClient(region=region)
    session_started = False
    try:
        logger.info("browse: BrowserClient created; calling start(identifier=%s)", BROWSER_ID)
        start_resp = client.start(identifier=BROWSER_ID)
        session_started = True
        logger.info("browse: start returned: %r", start_resp)
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
            result = text[:4000]
            logger.info("browse: returning %d chars to agent", len(result))
            return result
    except Exception as e:
        logger.exception("Browse tool failed for url=%s", url)
        return f"Browse failed: {type(e).__name__}: {e}"
    finally:
        if session_started:
            try:
                client.stop()
                logger.info("browse: BrowserClient session stopped")
            except Exception:
                logger.exception("browse: error stopping BrowserClient session")


# Configure the Bedrock model. temperature/max_tokens are first-class BedrockModel
# kwargs (they map to Converse inferenceConfig) — do not pass them via
# additional_request_fields, where they land in additionalModelRequestFields and
# are ignored, leaving max_tokens effectively unset (model default → throttling risk).
model_id = os.environ.get("MODEL_ID", "global.anthropic.claude-sonnet-4-5-20250929-v1:0")
model = BedrockModel(
    model_id=model_id,
    temperature=0.1,  # Lower temperature for more consistent results
    max_tokens=2048,
)

# Persona for the agent. With memory enabled the session manager injects the
# user's remembered facts into context automatically — no prompt stitching needed.
BASE_SYSTEM_PROMPT = "You're a helpful assistant. You can do simple math calculations, tell the weather, provide personalized greetings, and browse web pages."

TOOLS = [calculator, weather, greeting, browse]


def _build_agent(session_manager=None):
    """Construct the Strands agent, optionally wired to AgentCore Memory."""
    return Agent(
        model=model,
        tools=TOOLS,
        system_prompt=BASE_SYSTEM_PROMPT,
        session_manager=session_manager,
    )


@app.entrypoint
def bedrock_agent_runtime(payload, context):
    """Main entrypoint for the Runtime — invoke the agent for one turn.

    When memory is configured, AgentCoreMemorySessionManager transparently
    (1) recalls this actor's relevant long-term facts into context before the
    turn and (2) persists the conversation afterward — no manual retrieve/write.

    Recall keys on actor_id; short-term continuity keys on session_id:
    - session_id comes from the Runtime's own runtimeSessionId (context.session_id),
      so multi-turn context within one conversation is grouped correctly — including
      in the console playground, which auto-generates a session but never puts it in
      the payload. Falls back to a fresh id only if the runtime didn't supply one.
    - actor_id is app-level: not derived from the caller's IAM role. Pass it in the
      payload for per-user memory; otherwise everyone shares "default-user".
    """
    logger.info("Received payload: %s", json.dumps(payload))
    user_input = payload.get("prompt", "")
    actor_id   = payload.get("actor_id", "default-user")
    session_id = getattr(context, "session_id", None) or str(uuid.uuid4())
    logger.info("User input: %s (actor=%s, session=%s)", user_input, actor_id, session_id)

    # No memory configured — run a plain, stateless agent. str(result) yields the
    # agent's final text (Strands AgentResult.__str__), robust to tool-use/reasoning
    # blocks that manual content[0] indexing would trip over.
    if not MEMORY_ID:
        return str(_build_agent()(user_input))

    config = AgentCoreMemoryConfig(
        memory_id=MEMORY_ID,
        session_id=session_id,
        actor_id=actor_id,
        retrieval_config={
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
    # Run the app without any parameters - BedrockAgentCoreApp handles defaults
    logger.info("Starting Bedrock Agent Runtime with STRANDS framework")
    app.run()
