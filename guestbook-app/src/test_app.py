from unittest.mock import Mock, patch

import pytest


@pytest.fixture
def guestbook(monkeypatch, tmp_path):
    monkeypatch.setenv('BASE_PATH', 'demo')
    with patch('boto3.resource'):
        import app
    table = Mock()
    table.scan.return_value = {
        'Items': [{'GuestID': 'entry-1', 'Name': 'Alice', 'Message': 'Hello'}]
    }
    monkeypatch.setattr(app, 'table', table)
    monkeypatch.setattr(app, 'get_id_file_path', lambda: str(tmp_path))
    return app.app.test_client(), table


def test_home(guestbook):
    client, _ = guestbook
    response = client.get('/demo')
    assert response.status_code == 200
    assert b'Hello, World!' in response.data


def test_get_cannot_delete(guestbook):
    client, table = guestbook
    response = client.get('/demo?action=delete&guest_id=entry-1')
    assert response.status_code == 200
    table.delete_item.assert_not_called()


def test_post_deletes_entry(guestbook):
    client, table = guestbook
    response = client.post('/demo', data={
        'action': 'delete', 'guest_id': 'entry-1',
    })
    assert response.status_code == 302
    table.delete_item.assert_called_once_with(Key={'GuestID': 'entry-1'})
    table.put_item.assert_not_called()


def test_submission_still_works(guestbook):
    client, table = guestbook
    response = client.post('/demo', data={
        'name': 'Alice', 'message': 'Hello',
    })
    assert response.status_code == 302
    table.put_item.assert_called_once()
    table.delete_item.assert_not_called()
