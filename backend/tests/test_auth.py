import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.facility import FacilityModel
from app.models.user import UserModel
from app.core.security import hash_password


@pytest.fixture(autouse=True)
def setup_auth_test_data(db_session: Session):
    """Fixture ensuring test facilities and test users exist in the test DB."""
    # Ensure facilities exist
    phc_fac = db_session.query(FacilityModel).filter_by(facility_code="PHC_TEST").first()
    if not phc_fac:
        phc_fac = FacilityModel(
            facility_code="PHC_TEST",
            name="Test Primary Health Centre",
            facility_type="PHC",
            is_active=True,
        )
        db_session.add(phc_fac)

    dh_fac = db_session.query(FacilityModel).filter_by(facility_code="DH_TEST").first()
    if not dh_fac:
        dh_fac = FacilityModel(
            facility_code="DH_TEST",
            name="Test District Hospital",
            facility_type="DISTRICT_HOSPITAL",
            is_active=True,
        )
        db_session.add(dh_fac)
    db_session.commit()

    # Create active test PHC user
    phc_user = db_session.query(UserModel).filter_by(username="test_phc_worker").first()
    if not phc_user:
        phc_user = UserModel(
            username="test_phc_worker",
            email="phc_worker@test.org",
            phone="+919800000001",
            password_hash=hash_password("Pass123!"),
            role="PHC_STAFF",
            facility_id="PHC_TEST",
            is_active=True,
        )
        db_session.add(phc_user)

    # Create active test Hospital user
    hosp_user = db_session.query(UserModel).filter_by(username="test_hosp_worker").first()
    if not hosp_user:
        hosp_user = UserModel(
            username="test_hosp_worker",
            email="hosp_worker@test.org",
            phone="+919800000002",
            password_hash=hash_password("Pass123!"),
            role="HOSPITAL_STAFF",
            facility_id="DH_TEST",
            is_active=True,
        )
        db_session.add(hosp_user)

    # Create inactive test user
    inactive_user = db_session.query(UserModel).filter_by(username="test_inactive_worker").first()
    if not inactive_user:
        inactive_user = UserModel(
            username="test_inactive_worker",
            email="inactive@test.org",
            phone="+919800000003",
            password_hash=hash_password("Pass123!"),
            role="PHC_STAFF",
            facility_id="PHC_TEST",
            is_active=False,
        )
        db_session.add(inactive_user)

    db_session.commit()


def test_login_success(client: TestClient):
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "test_phc_worker", "password": "Pass123!"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["username"] == "test_phc_worker"
    assert data["user"]["role"] == "PHC_STAFF"
    assert data["user"]["facility_id"] == "PHC_TEST"


def test_login_invalid_password(client: TestClient):
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "test_phc_worker", "password": "WrongPassword"},
    )
    assert response.status_code == 401
    assert "detail" in response.json()


def test_login_inactive_user(client: TestClient):
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "test_inactive_worker", "password": "Pass123!"},
    )
    assert response.status_code == 403
    assert "inactive" in response.json()["detail"].lower()


def test_get_me_valid_token(client: TestClient):
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"username": "test_phc_worker", "password": "Pass123!"},
    )
    token = login_resp.json()["access_token"]

    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["username"] == "test_phc_worker"
    assert data["facility_id"] == "PHC_TEST"
    assert data["facility"]["facility_code"] == "PHC_TEST"


def test_get_me_missing_token(client: TestClient):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401


def test_get_me_invalid_token(client: TestClient):
    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer invalid.token.value"},
    )
    assert response.status_code == 401


def test_demo_users_seed_and_auth(client: TestClient, db_session: Session):
    from app.db.seed import seed_facilities_and_users
    
    # Run seed twice to verify idempotency
    seed_facilities_and_users(db_session)
    seed_facilities_and_users(db_session)

    # 1. Test PHC demo user
    resp_phc = client.post("/api/v1/auth/login", json={"username": "phc", "password": "12345678"})
    assert resp_phc.status_code == 200
    phc_data = resp_phc.json()
    assert phc_data["user"]["username"] == "phc"
    assert phc_data["user"]["role"] == "PHC_STAFF"
    assert phc_data["user"]["facility_id"] == "PHC-TEST"

    # 2. Test Hospital demo user
    resp_hosp = client.post("/api/v1/auth/login", json={"username": "hosp", "password": "12345678"})
    assert resp_hosp.status_code == 200
    hosp_data = resp_hosp.json()
    assert hosp_data["user"]["username"] == "hosp"
    assert hosp_data["user"]["role"] == "HOSPITAL_STAFF"
    assert hosp_data["user"]["facility_id"] == "DH-TEST"

    # 3. Test Patient demo user
    resp_patient = client.post("/api/v1/auth/login", json={"username": "patient", "password": "12345678"})
    assert resp_patient.status_code == 200
    patient_data = resp_patient.json()
    assert patient_data["user"]["username"] == "patient"
    assert patient_data["user"]["role"] == "PATIENT"
    assert patient_data["user"]["facility_id"] == "PHC-TEST"

