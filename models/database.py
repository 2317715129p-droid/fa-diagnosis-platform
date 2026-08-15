"""SQLAlchemy database models and helpers for the FA diagnosis backend."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Generator

from sqlalchemy import Boolean, DateTime, Integer, String, Text, create_engine, event, select, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from config import DATABASE_URL

# Agent push health thresholds (plan defaults)
ONLINE_WITHIN = timedelta(minutes=10)
STALE_WITHIN = timedelta(minutes=30)

_ASSET_EXTRA_COLUMNS = (
    ("last_seen_at", "DATETIME"),
    ("last_log_text", "TEXT"),
    ("last_log_at", "DATETIME"),
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_aware(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def compute_online_status(last_seen_at: datetime | None) -> str:
    """Return online | stale | offline | never based on last_seen_at."""
    seen = _ensure_aware(last_seen_at)
    if seen is None:
        return "never"
    age = _utcnow() - seen
    if age <= ONLINE_WITHIN:
        return "online"
    if age <= STALE_WITHIN:
        return "stale"
    return "offline"


class Base(DeclarativeBase):
    pass


class Asset(Base):
    __tablename__ = "assets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    asset_id: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    server_model: Mapped[str | None] = mapped_column(String(200), nullable=True)
    vendor: Mapped[str | None] = mapped_column(String(100), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(50), nullable=True)
    bmc_address: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="normal")
    last_diagnosis_time: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_log_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_log_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, onupdate=_utcnow)


class DiagnosisReport(Base):
    __tablename__ = "diagnosis_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    asset_id: Mapped[str] = mapped_column(String(100), nullable=False)
    report_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    severity: Mapped[str | None] = mapped_column(String(20), nullable=True)
    confidence: Mapped[str | None] = mapped_column(String(20), nullable=True)
    kb_version: Mapped[str | None] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)


engine = create_engine(
    DATABASE_URL,
    connect_args={"timeout": 2000, "check_same_thread": False},
)


@event.listens_for(engine, "connect")
def _enable_wal_mode(dbapi_connection, connection_record) -> None:
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.close()


SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def _migrate_assets_columns() -> None:
    """Add collect-related columns on existing SQLite DBs (create_all won't ALTER)."""
    with engine.begin() as conn:
        rows = conn.execute(text("PRAGMA table_info(assets)")).fetchall()
        existing = {row[1] for row in rows}
        for col_name, col_type in _ASSET_EXTRA_COLUMNS:
            if col_name not in existing:
                conn.execute(text(f"ALTER TABLE assets ADD COLUMN {col_name} {col_type}"))


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    _migrate_assets_columns()


@contextmanager
def get_session() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def save_report(
    asset_id: str,
    report_content: str,
    severity: str,
    confidence: str,
) -> DiagnosisReport:
    with get_session() as session:
        report = DiagnosisReport(
            asset_id=asset_id,
            report_content=report_content,
            severity=severity,
            confidence=confidence,
        )
        session.add(report)
        session.flush()
        session.refresh(report)
        session.expunge(report)
        return report.id


def get_reports(asset_id: str) -> list[dict]:
    with get_session() as session:
        reports = session.execute(
            select(DiagnosisReport)
            .where(DiagnosisReport.asset_id == asset_id)
            .order_by(DiagnosisReport.created_at.desc())
        ).scalars().all()
        return [
            {
                "id": report.id,
                "asset_id": report.asset_id,
                "report_content": report.report_content,
                "severity": report.severity,
                "confidence": report.confidence,
                "kb_version": report.kb_version,
                "created_at": report.created_at,
                "archived": report.archived,
            }
            for report in reports
        ]


def archive_report(report_id: int) -> str | None:
    with get_session() as session:
        report = session.get(DiagnosisReport, report_id)
        if report is None:
            return None
        report.archived = True
        return report.asset_id


def update_asset_status(asset_id: str, status: str) -> bool:
    with get_session() as session:
        asset = session.execute(
            select(Asset).where(Asset.asset_id == asset_id)
        ).scalar_one_or_none()
        if asset is None:
            return False
        asset.status = status
        asset.updated_at = _utcnow()
        return True


def upsert_asset(
    asset_id: str,
    server_model: str | None,
    vendor: str | None,
    ip_address: str | None,
    last_log_text: str | None = None,
) -> Asset:
    now = _utcnow()
    with get_session() as session:
        asset = session.execute(
            select(Asset).where(Asset.asset_id == asset_id)
        ).scalar_one_or_none()
        if asset is None:
            asset = Asset(
                asset_id=asset_id,
                server_model=server_model,
                vendor=vendor,
                ip_address=ip_address,
                last_seen_at=now,
            )
            if last_log_text is not None:
                asset.last_log_text = last_log_text
                asset.last_log_at = now
            session.add(asset)
        else:
            asset.server_model = server_model
            if vendor is not None:
                asset.vendor = vendor
            if ip_address is not None:
                asset.ip_address = ip_address
            asset.last_seen_at = now
            asset.updated_at = now
            if last_log_text is not None:
                asset.last_log_text = last_log_text
                asset.last_log_at = now
        session.flush()
        session.refresh(asset)
        session.expunge(asset)
        return asset


def _iso(dt: datetime | None) -> str | None:
    aware = _ensure_aware(dt)
    if aware is None:
        return None
    return aware.isoformat().replace("+00:00", "Z")


def _asset_to_list_item(asset: Asset) -> dict:
    last_seen = asset.last_seen_at
    return {
        "asset_id": asset.asset_id,
        "server_model": asset.server_model,
        "ip_address": asset.ip_address,
        "status": asset.status,
        "last_seen_at": _iso(last_seen),
        "last_log_at": _iso(asset.last_log_at),
        "has_log": bool(asset.last_log_text and asset.last_log_text.strip()),
        "online_status": compute_online_status(last_seen),
    }


def list_assets() -> list[dict]:
    with get_session() as session:
        assets = list(
            session.execute(select(Asset)).scalars().all()
        )
        assets.sort(
            key=lambda a: (
                a.last_seen_at is None,
                -(a.last_seen_at.timestamp() if a.last_seen_at else 0),
                a.asset_id,
            )
        )
        return [_asset_to_list_item(a) for a in assets]


def get_asset_logs(asset_id: str) -> dict | None:
    with get_session() as session:
        asset = session.execute(
            select(Asset).where(Asset.asset_id == asset_id)
        ).scalar_one_or_none()
        if asset is None:
            return None
        return {
            "asset_id": asset.asset_id,
            "server_model": asset.server_model,
            "status": asset.status,
            "last_log_text": asset.last_log_text or "",
            "last_seen_at": _iso(asset.last_seen_at),
            "last_log_at": _iso(asset.last_log_at),
            "online_status": compute_online_status(asset.last_seen_at),
        }


def delete_asset(asset_id: str) -> bool:
    """Remove asset inventory row. Does not delete diagnosis_reports history."""
    with get_session() as session:
        asset = session.execute(
            select(Asset).where(Asset.asset_id == asset_id)
        ).scalar_one_or_none()
        if asset is None:
            return False
        session.delete(asset)
        return True
