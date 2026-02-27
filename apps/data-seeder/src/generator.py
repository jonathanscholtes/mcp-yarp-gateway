import os
import random
import time
import uuid
from datetime import datetime, timezone

from pymongo import MongoClient


MONGODB_CONNECTION_STRING = os.getenv("MONGODB_CONNECTION_STRING", "")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "contracts_db")

CONTRACTS_COLLECTION = os.getenv("MONGODB_CONTRACTS_COLLECTION", "contracts")
RISK_MEMOS_COLLECTION = os.getenv("MONGODB_RISK_MEMOS_COLLECTION", "risk_memos")
MARKET_COLLECTION = os.getenv("MONGODB_MARKET_COLLECTION", "market_data")

GENERATOR_MODE = os.getenv("GENERATOR_MODE", "continuous").lower()
GENERATOR_BATCH_SIZE = int(os.getenv("GENERATOR_BATCH_SIZE", "20"))
GENERATOR_INTERVAL_SECONDS = int(os.getenv("GENERATOR_INTERVAL_SECONDS", "30"))
GENERATOR_SEED = int(os.getenv("GENERATOR_SEED", "42"))


CURRENCY_PAIRS = ["EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "USD/CAD"]
DESKS = ["Rates", "FX", "Credit", "Commodities", "Equities"]
BOOKS = ["BOOK-NA", "BOOK-EU", "BOOK-APAC"]
STATUSES = ["new", "active", "amended", "closed"]


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def random_contract() -> dict:
    notional = random.randint(50_000, 5_000_000)
    ccy_pair = random.choice(CURRENCY_PAIRS)
    status = random.choice(STATUSES)
    return {
        "contractId": str(uuid.uuid4()),
        "book": random.choice(BOOKS),
        "desk": random.choice(DESKS),
        "counterparty": f"CP-{random.randint(1000, 9999)}",
        "currencyPair": ccy_pair,
        "notional": notional,
        "maturityDate": f"{random.randint(2026, 2032)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}",
        "status": status,
        "createdAt": utc_now(),
        "updatedAt": utc_now(),
    }


def random_risk_memo(contract_id: str) -> dict:
    var_95 = round(random.uniform(5_000, 200_000), 2)
    dv01 = round(random.uniform(-80_000, 80_000), 2)
    severity = "high" if abs(dv01) > 50_000 or var_95 > 100_000 else "medium"
    return {
        "memoId": str(uuid.uuid4()),
        "contractId": contract_id,
        "summary": "Synthetic risk memo generated for MCP testing.",
        "var95": var_95,
        "dv01": dv01,
        "severity": severity,
        "createdAt": utc_now(),
    }


def random_market_point() -> dict:
    pair = random.choice(CURRENCY_PAIRS)
    spot = round(random.uniform(0.75, 1.45), 6)
    vol = round(random.uniform(0.05, 0.25), 4)
    return {
        "snapshotId": str(uuid.uuid4()),
        "currencyPair": pair,
        "spot": spot,
        "volatility": vol,
        "asOf": utc_now(),
        "source": "mongo-data-generator",
    }


def ensure_indexes(db):
    db[CONTRACTS_COLLECTION].create_index("contractId", unique=True)
    db[CONTRACTS_COLLECTION].create_index("desk")
    db[RISK_MEMOS_COLLECTION].create_index("contractId")
    db[RISK_MEMOS_COLLECTION].create_index("createdAt")
    db[MARKET_COLLECTION].create_index([("currencyPair", 1), ("asOf", -1)])


def write_batch(db):
    contracts = [random_contract() for _ in range(GENERATOR_BATCH_SIZE)]
    db[CONTRACTS_COLLECTION].insert_many(contracts, ordered=False)

    memos = [random_risk_memo(contract["contractId"]) for contract in contracts]
    db[RISK_MEMOS_COLLECTION].insert_many(memos, ordered=False)

    market_points = [random_market_point() for _ in range(GENERATOR_BATCH_SIZE)]
    db[MARKET_COLLECTION].insert_many(market_points, ordered=False)

    print(
        f"[{utc_now().isoformat()}] inserted {len(contracts)} contracts, "
        f"{len(memos)} risk memos, {len(market_points)} market records"
    )


def validate_env() -> None:
    if not MONGODB_CONNECTION_STRING:
        raise ValueError("MONGODB_CONNECTION_STRING is required")
    if GENERATOR_BATCH_SIZE < 1:
        raise ValueError("GENERATOR_BATCH_SIZE must be >= 1")
    if GENERATOR_MODE not in {"once", "continuous"}:
        raise ValueError("GENERATOR_MODE must be 'once' or 'continuous'")


def main() -> None:
    validate_env()
    random.seed(GENERATOR_SEED)

    client = MongoClient(MONGODB_CONNECTION_STRING)
    db = client[MONGODB_DATABASE]

    try:
        ensure_indexes(db)
        print(
            f"Connected to MongoDB database '{MONGODB_DATABASE}'. "
            f"Mode={GENERATOR_MODE}, BatchSize={GENERATOR_BATCH_SIZE}, "
            f"Interval={GENERATOR_INTERVAL_SECONDS}s"
        )

        if GENERATOR_MODE == "once":
            write_batch(db)
            return

        while True:
            write_batch(db)
            time.sleep(GENERATOR_INTERVAL_SECONDS)
    finally:
        client.close()


if __name__ == "__main__":
    main()
