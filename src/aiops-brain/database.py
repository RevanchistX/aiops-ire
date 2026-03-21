"""Async SQLAlchemy engine and session factory.

All database I/O in aiops-brain uses the AsyncSession acquired via get_db().
"""

import os

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

# asyncpg driver requires postgresql+asyncpg:// scheme
_raw_url: str = os.environ["DATABASE_URL"]
ASYNC_DATABASE_URL: str = _raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)

engine = create_async_engine(
    ASYNC_DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    expire_on_commit=False,
    class_=AsyncSession,
)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    """FastAPI dependency that yields a managed AsyncSession."""
    async with AsyncSessionLocal() as session:
        yield session
