"""Pydantic models for interseed."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class Idea(BaseModel):
    id: str
    thesis: str
    evidence: list[str] = Field(default_factory=list)
    confidence: float = 0.1
    maturity: Literal["seed", "sprouting", "growing", "mature"] = "seed"
    keywords: list[str] = Field(default_factory=list)
    open_questions: list[str] = Field(default_factory=list)
    garden_id: str | None = None
    source: str = "cli"
    graduated_bead_id: str | None = None
    enriched: bool = False
    locked_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class RefinementLog(BaseModel):
    id: str
    idea_id: str
    trigger: Literal["scheduled", "event", "manual"] = "scheduled"
    summary: str
    confidence_before: float
    confidence_after: float
    new_evidence: list[str] = Field(default_factory=list)
    context_hash: str | None = None
    created_at: datetime


class Annotation(BaseModel):
    id: str
    idea_id: str
    source: str
    annotation_type: Literal["comment", "steer", "graduation_approval"]
    body: str
    created_at: datetime
