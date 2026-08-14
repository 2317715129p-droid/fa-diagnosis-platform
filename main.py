# Fix note: WebSocket flow was already correct; keep integrated pipeline and
# ensure imports/signature match the fixed run_dify_workflow(log_text, server_id).

import json

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from api.diagnose import router as diagnose_router
from api.agent_deploy import router as agent_router
from services.masking import enforce_data_masking
from services.dify_client import run_dify_workflow
from services.report_validator import validate_and_fix_report
from models.database import init_db, save_report

app = FastAPI(title="FA Diagnosis System MVP", version="0.1.0")

app.include_router(diagnose_router, prefix="/api")
app.include_router(agent_router, prefix="/api")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/download", StaticFiles(directory="static"), name="download")


@app.on_event("startup")
async def startup_event():
    init_db()
    print("Server started")


@app.get("/")
async def root():
    return {
        "service": "FA Diagnosis System API",
        "status": "running",
        "ui_hint": "Open the React UI at http://<this-host>:3000 (not port 8000)",
        "health": "/health",
        "api_docs": "/docs",
        "agent_install": "/api/agent/install.sh?server_id=Node-01",
    }


@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}


@app.websocket("/ws/diagnose")
async def ws_diagnose(websocket: WebSocket):
    await websocket.accept()
    print("Client connected")
    try:
        while True:
            data = await websocket.receive_text()
            payload = json.loads(data)
            action = payload.get("action")
            server_id = payload.get("server_id", "")
            log_text = payload.get("log_text", "")
            print(f"Received diagnosis request: action={action}, server_id={server_id}")
            try:
                masked_log = enforce_data_masking(log_text)
                chunks: list[str] = []
                async for text in run_dify_workflow(masked_log, server_id):
                    chunks.append(text)
                    await websocket.send_json({"type": "chunk", "content": text})

                print(f"总共收到 {len(chunks)} 个文本块")
                full_report = "".join(chunks)
                validated_report = validate_and_fix_report(full_report, {})
                report_id = save_report(
                    asset_id=server_id,
                    report_content=validated_report,
                    severity="unknown",
                    confidence="unknown",
                )
                await websocket.send_json(
                    {
                        "type": "done",
                        "report": validated_report,
                        "report_id": report_id,
                    }
                )
                print(f"Diagnosis complete for server: {server_id}, report_id={report_id}")
            except WebSocketDisconnect:
                print("Client disconnected during diagnosis")
                break
            except Exception as exc:
                print(f"Diagnosis error: {exc}")
                try:
                    await websocket.send_json(
                        {"type": "error", "message": str(exc) or "Diagnosis failed"}
                    )
                except Exception:
                    break
    except WebSocketDisconnect:
        print("Client disconnected")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
