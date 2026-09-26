from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.db.database import Base


class UserModel(Base):
    """SQLAlchemy model representing an authenticated user in RelyCare."""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    username = Column(String(128), unique=True, index=True, nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=True)
    phone = Column(String(64), nullable=True)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(64), nullable=False)  # PHC_STAFF, HOSPITAL_STAFF, or PATIENT
    facility_id = Column(String(64), ForeignKey("facilities.facility_code"), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<UserModel(username='{self.username}', role='{self.role}', facility='{self.facility_id}')>"
