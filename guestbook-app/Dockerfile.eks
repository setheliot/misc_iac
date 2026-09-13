FROM python:3-alpine

# Copy requirements.txt to the container
COPY requirements.txt /src/requirements.txt

# Install the dependencies listed in requirements.txt
RUN pip install -r /src/requirements.txt

WORKDIR /src

# Copy the application code into the container
COPY ./src /src/

# Run the application
CMD ["python", "app.py"]
