import os
import pytest
from unittest.mock import MagicMock
from app.db.seed import is_demo_seeding_allowed, seed_facilities_and_users, seed_development_data
from app.models.facility import FacilityModel


def test_is_demo_seeding_allowed_development(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.delenv("ALLOW_DEMO_SEEDING", raising=False)
    assert is_demo_seeding_allowed() is True


def test_is_demo_seeding_allowed_production_default(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.delenv("ALLOW_DEMO_SEEDING", raising=False)
    assert is_demo_seeding_allowed() is False


def test_is_demo_seeding_allowed_production_override(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("ALLOW_DEMO_SEEDING", "true")
    assert is_demo_seeding_allowed() is True


def test_seed_facilities_and_users_skipped_in_production(monkeypatch, db_session):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.delenv("ALLOW_DEMO_SEEDING", raising=False)

    # Ensure clean test state
    initial_facilities_count = db_session.query(FacilityModel).count()

    # Call seeding without force
    seed_facilities_and_users(db_session, force=False)

    # Database writes must not occur
    assert db_session.query(FacilityModel).count() == initial_facilities_count


def test_seed_facilities_and_users_runs_when_forced_or_allowed(monkeypatch, db_session):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.delenv("ALLOW_DEMO_SEEDING", raising=False)

    # Force should allow seeding
    seed_facilities_and_users(db_session, force=True)

    phc = db_session.query(FacilityModel).filter(FacilityModel.facility_code == "PHC-TEST").first()
    assert phc is not None


def test_seed_development_data_raises_in_production(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.delenv("ALLOW_DEMO_SEEDING", raising=False)

    with pytest.raises(RuntimeError, match="Demo user seeding is blocked in production environment"):
        seed_development_data()
