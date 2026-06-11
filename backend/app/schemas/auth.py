"""Auth request/response schemas — these define the OpenAPI contract the Flutter
client is generated from. One schema per endpoint, names mirror routes."""
from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    username: str
    password: str
    device_key: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    role: str
    station: str | None
    full_name: str
    language: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class PinSwitchRequest(BaseModel):
    device_key: str
    username: str
    pin: str = Field(min_length=4, max_length=8)


class OtpRequestRequest(BaseModel):
    phone: str


class OtpRequestResponse(BaseModel):
    sent: bool
    dev_code: str | None = None  # mock OTP only; removed with real SMS


class OtpVerifyRequest(BaseModel):
    phone: str
    code: str
