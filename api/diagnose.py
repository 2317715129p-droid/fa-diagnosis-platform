"""Diagnosis API routes for the FA FastAPI backend."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services.masking import enforce_data_masking
from services.dify_client import translate_report
from models.database import (
    save_report,
    upsert_asset,
    archive_report,
    update_asset_status,
    get_reports,
    list_assets,
    get_asset_logs,
    delete_asset,
)

router = APIRouter()


class DiagnoseRequest(BaseModel):
    log_text: str
    server_id: str


class CollectRequest(BaseModel):
    server_id: str
    server_model: str
    sel_logs: list[str] = Field(default_factory=list)


class ArchiveRequest(BaseModel):
    report_id: int


class TranslateRequest(BaseModel):
    report_zh: str


@router.post("/diagnose")
def diagnose(body: DiagnoseRequest) -> dict:
    masked_log = enforce_data_masking(body.log_text)
    report_id = save_report(
        asset_id=body.server_id,
        report_content=masked_log,
        severity="unknown",
        confidence="unknown",
    )
    return {"status": "ok", "report_id": report_id}


@router.post("/collect")
def collect(body: CollectRequest) -> dict:
    masked_lines = [enforce_data_masking(log) for log in body.sel_logs]
    masked_text = "\n".join(line for line in masked_lines if line is not None)
    upsert_asset(
        asset_id=body.server_id,
        server_model=body.server_model,
        vendor=None,
        ip_address=None,
        last_log_text=masked_text,
    )
    return {
        "status": "ok",
        "asset_id": body.server_id,
        "lines": len(masked_lines),
        "message": "Logs received",
    }


@router.get("/assets")
def assets() -> list[dict]:
    return list_assets()


@router.get("/assets/{asset_id}/logs")
def asset_logs(asset_id: str) -> dict:
    result = get_asset_logs(asset_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Asset not found")
    return result


@router.delete("/assets/{asset_id}")
def remove_asset(asset_id: str) -> dict:
    """Remove asset from the monitoring list (center DB only; does not uninstall agent)."""
    if not delete_asset(asset_id):
        raise HTTPException(status_code=404, detail="Asset not found")
    return {"status": "ok", "asset_id": asset_id, "message": "Asset removed"}


@router.post("/archive")
def archive(body: ArchiveRequest) -> dict:
    result = archive_report(body.report_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Report not found")
    asset_id = result["asset_id"] if isinstance(result, dict) else result
    if asset_id is not None:
        update_asset_status(asset_id, "normal")
    return {"status": "ok", "message": "Report archived"}


@router.post("/translate")
async def translate(body: TranslateRequest) -> dict:
    """Translate Chinese FA report to English via Dify translate workflow."""
    try:
        report_en = await translate_report(body.report_zh)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"status": "ok", "report_en": report_en}


@router.get("/reports/{asset_id}")
def reports(asset_id: str) -> list[dict]:
    return get_reports(asset_id)
