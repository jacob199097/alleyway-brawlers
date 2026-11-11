-- The website's visit counter (site/visits.js): totals per day only, nothing about any one visitor.
-- kind 'total' (key 'views', 'visitors', 'phone'), 'page' (key = the page's address), 'from' (key = the site
-- a visitor came from). Days older than about 400 days are deleted.
CREATE TABLE IF NOT EXISTS site_counts (
    day   DATE NOT NULL,
    kind  TEXT NOT NULL,
    key   TEXT NOT NULL,
    n     INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (day, kind, key)
);
