import os
import logging
from sqlalchemy.orm import Session
from app.db.database import SessionLocal
from app.models.facility import FacilityModel
from app.models.user import UserModel
from app.core.security import hash_password

logger = logging.getLogger("relycare.db.seed")


def is_demo_seeding_allowed() -> bool:
    """Explicit environment/configuration guard against accidentally seeding demo credentials into production."""
    env = os.getenv("ENVIRONMENT", "development").lower()
    allow_seed_env = os.getenv("ALLOW_DEMO_SEEDING")
    if allow_seed_env is not None:
        return allow_seed_env.strip().lower() in ("true", "1", "yes")
    # By default, allow demo seeding in non-production environments
    return env not in ("production", "prod")


def seed_facilities_and_users(db: Session, force: bool = False) -> None:
    """Idempotently seed required facilities and development/demo users into PostgreSQL."""
    # 1. Seed or update required facilities
    facilities_data = [
        {
            "facility_code": "PHC-TEST",
            "name": "Primary Health Centre Test",
            "facility_type": "PHC",
            "is_active": True,
        },
        {
            "facility_code": "DH-TEST",
            "name": "District Hospital Test",
            "facility_type": "DISTRICT_HOSPITAL",
            "is_active": True,
        },
    ]

    for f_data in facilities_data:
        fac = db.query(FacilityModel).filter(FacilityModel.facility_code == f_data["facility_code"]).first()
        if not fac:
            fac = FacilityModel(
                facility_code=f_data["facility_code"],
                name=f_data["name"],
                facility_type=f_data["facility_type"],
                is_active=f_data["is_active"],
            )
            db.add(fac)
        else:
            fac.name = f_data["name"]
            fac.facility_type = f_data["facility_type"]
            fac.is_active = f_data["is_active"]
    db.commit()

    # Guard demo users against production deployment unless explicitly allowed or forced
    if not is_demo_seeding_allowed() and not force:
        logger.warning(
            "Demo user seeding skipped: ENVIRONMENT is set to production and ALLOW_DEMO_SEEDING is not enabled."
        )
        return

    # 2. Seed standard demo users (Password: 12345678)
    demo_users_data = [
        {
            "username": "phc",
            "password": "12345678",
            "email": "phc@relycare.local",
            "phone": "+919800000101",
            "role": "PHC_STAFF",
            "facility_id": "PHC-TEST",
            "is_active": True,
        },
        {
            "username": "hosp",
            "password": "12345678",
            "email": "hosp@relycare.local",
            "phone": "+919800000202",
            "role": "HOSPITAL_STAFF",
            "facility_id": "DH-TEST",
            "is_active": True,
        },
        {
            "username": "patient",
            "password": "12345678",
            "email": "patient@relycare.local",
            "phone": "+919800000303",
            "role": "PATIENT",
            "facility_id": "PHC-TEST",
            "is_active": True,
        },
    ]

    for u_data in demo_users_data:
        user = db.query(UserModel).filter(UserModel.username == u_data["username"]).first()
        if not user:
            user = UserModel(
                username=u_data["username"],
                email=u_data["email"],
                phone=u_data["phone"],
                password_hash=hash_password(u_data["password"]),
                role=u_data["role"],
                facility_id=u_data["facility_id"],
                is_active=u_data["is_active"],
            )
            db.add(user)
        else:
            user.password_hash = hash_password(u_data["password"])
            user.role = u_data["role"]
            user.facility_id = u_data["facility_id"]
            user.is_active = u_data["is_active"]
    db.commit()

    # 3. Seed optional environment-based legacy users if configured
    phc_password = os.getenv("DEV_PHC_PASSWORD")
    dh_password = os.getenv("DEV_HOSPITAL_PASSWORD")

    if phc_password:
        phc_username = os.getenv("DEV_PHC_USERNAME", "phc_user1")
        u_phc = db.query(UserModel).filter(UserModel.username == phc_username).first()
        if not u_phc:
            u_phc = UserModel(
                username=phc_username,
                email="phc_user1@relycare.local",
                phone="+919800000111",
                password_hash=hash_password(phc_password),
                role="PHC_STAFF",
                facility_id="PHC-TEST",
                is_active=True,
            )
            db.add(u_phc)
        else:
            u_phc.password_hash = hash_password(phc_password)
            u_phc.is_active = True
        db.commit()

    if dh_password:
        dh_username = os.getenv("DEV_HOSPITAL_USERNAME", "hosp_user1")
        u_dh = db.query(UserModel).filter(UserModel.username == dh_username).first()
        if not u_dh:
            u_dh = UserModel(
                username=dh_username,
                email="hosp_user1@relycare.local",
                phone="+919800000222",
                password_hash=hash_password(dh_password),
                role="HOSPITAL_STAFF",
                facility_id="DH-TEST",
                is_active=True,
            )
            db.add(u_dh)
        else:
            u_dh.password_hash = hash_password(dh_password)
            u_dh.is_active = True
        db.commit()


def seed_development_data():
    """Entrypoint for executing the development seed script."""
    if not is_demo_seeding_allowed():
        raise RuntimeError(
            "Demo user seeding is blocked in production environment. "
            "Set ALLOW_DEMO_SEEDING=true if you explicitly intend to seed demo credentials."
        )

    db = SessionLocal()
    try:
        seed_facilities_and_users(db)
        print("Development facilities and demo users seeded successfully.")
    except Exception as e:
        db.rollback()
        print(f"Error seeding development data: {e}")
        raise e
    finally:
        db.close()


if __name__ == "__main__":
    seed_development_data()

