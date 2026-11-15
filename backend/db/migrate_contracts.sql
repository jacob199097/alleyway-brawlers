-- Contracts (economy/contracts.js): a goal bought in the shop for Karat, good for the next few eligible
-- matches; done, it pays out more than it cost; not done in time, the Karat is gone. One active at a time,
-- and each of the day's offers can be bought once a day.
CREATE TABLE IF NOT EXISTS player_contracts (
    id           SERIAL      PRIMARY KEY,
    player_id    UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    day          DATE        NOT NULL,                 -- the (UTC) day of the offer it was bought from
    goal         TEXT        NOT NULL,                 -- a key of GOALS in economy/contract_settings.js
    price        INT         NOT NULL,
    payout       INT         NOT NULL,
    matches_left INT         NOT NULL,
    status       TEXT        NOT NULL DEFAULT 'active', -- active | done | failed
    bought_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at     TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS player_contracts_one_active ON player_contracts (player_id) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS player_contracts_once_a_day ON player_contracts (player_id, day, goal);
