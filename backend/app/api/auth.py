"""Auth router — HTTP concerns only; logic in services/auth.py (CLAUDE.md never-do)."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.schemas.auth import (LoginRequest, LogoutRequest, OtpRequestRequest,
                              OtpRequestResponse, OtpVerifyRequest, PinSwitchRequest,
                              RefreshRequest, TokenResponse)
from app.services import auth as svc

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    return svc.login(db, body.username, body.password, body.device_key)


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    return svc.refresh(db, body.refresh_token)


@router.post("/logout", status_code=204)
def logout(body: LogoutRequest, db: Session = Depends(get_db)):
    svc.logout(db, body.refresh_token)


@router.post("/pin-switch", response_model=TokenResponse)
def pin_switch(body: PinSwitchRequest, db: Session = Depends(get_db)):
    return svc.pin_switch(db, body.device_key, body.username, body.pin)


@router.post("/vendor-otp/request", response_model=OtpRequestResponse)
def vendor_otp_request(body: OtpRequestRequest, db: Session = Depends(get_db)):
    return svc.vendor_otp_request(db, body.phone)


@router.post("/vendor-otp/verify", response_model=TokenResponse)
def vendor_otp_verify(body: OtpVerifyRequest, db: Session = Depends(get_db)):
    return svc.vendor_otp_verify(db, body.phone, body.code)
