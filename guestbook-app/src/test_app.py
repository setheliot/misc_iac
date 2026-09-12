from app import app
import json

def test_home():
    response = app.test_client().get('/')

    assert response.status_code == 200
    assert b'Hello, World!' in response.data

# add more tests here