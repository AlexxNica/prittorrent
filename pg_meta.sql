CREATE TABLE users ("name" TEXT NOT NULL,
                    "email" TEXT NOT NULL,
                    "salt" BYTEA,
                    "salted" BYTEA,
                    "title" TEXT,
                    "image" TEXT,
                    "homepage" TEXT,
                    PRIMARY KEY ("name"));

CREATE TABLE feeds ("url" TEXT NOT NULL,
                    "last_update" TIMESTAMP,
                    "etag" TEXT,
                    "last_modified" TEXT,
                    "error" TEXT,
                    "title" TEXT,
                    "lang" TEXT,
                    "summary" TEXT,
                    "homepage" TEXT,
                    "image" TEXT,
                    "xml" TEXT,
                    "torrentify" BOOL DEFAULT TRUE,
                    PRIMARY KEY ("url"));

CREATE TABLE user_feeds ("user" TEXT NOT NULL REFERENCES "users" ("name"),
                         "slug" TEXT NOT NULL,
                         "feed" TEXT NOT NULL REFERENCES "feeds" ("url"),
                         "public" BOOL,
                         "title" TEXT,
                         PRIMARY KEY ("user", "slug"));

CREATE OR REPLACE FUNCTION add_user_feed(
        "f_user" TEXT,
        "f_slug" TEXT,
        "f_url" TEXT
) RETURNS BOOL AS $$
    DECLARE
        is_new BOOL := TRUE;
    BEGIN
        SELECT COUNT(url) < 1 INTO is_new
          FROM feeds WHERE url=f_url;
        IF is_new THEN
            INSERT INTO feeds (url) VALUES (f_url);
        END IF;
        INSERT INTO user_feeds
            ("user", "slug", "feed")
            VALUES (f_user, f_slug, f_url);
        RETURN is_new;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION feed_to_update(
       update_interval INTERVAL,
       OUT next_url TEXT, OUT wait INTERVAL
   ) RETURNS RECORD AS $$
    DECLARE
        next_feed RECORD;
    BEGIN
        SELECT "url", "last_update"
          INTO next_feed
          FROM "feeds"
      ORDER BY "last_update" ASC NULLS FIRST
         LIMIT 1
           FOR UPDATE;

        next_url := next_feed.url;
        IF next_feed.last_update IS NULL THEN
           next_feed.last_update = '1970-01-01 00:00:00';
        END IF;
        wait := next_feed.last_update + update_interval - CURRENT_TIMESTAMP;

        IF wait <= '0'::INTERVAL THEN
           UPDATE "feeds"
              SET "last_update"=CURRENT_TIMESTAMP
            WHERE "url"=next_url;
        END IF;
    END;
$$ LANGUAGE plpgsql;


-- Check this with: select * from enclosure_torrents where info_hash not in (select info_hash from torrents);
-- Or add a constraint on info_hash with either NULL or FOREIGN KEY torrents (info_hash)
CREATE TABLE enclosure_torrents ("url" TEXT NOT NULL PRIMARY KEY,
                                 last_update TIMESTAMP,
                                 error TEXT,
                                 info_hash BYTEA);

CREATE TABLE torrents ("info_hash" BYTEA PRIMARY KEY,
                       "name" TEXT,
                       "size" BIGINT,
                       "torrent" BYTEA);

CREATE OR REPLACE VIEW active_users AS
    SELECT "user",
           COUNT(DISTINCT slug) as "feeds",
           ARRAY_AGG(DISTINCT "lang") AS langs,
           ARRAY_AGG(DISTINCT "type") AS types
      FROM user_feeds
      JOIN (SELECT "url", "lang", "type"
              FROM feeds
              JOIN feed_types ON (feeds.url=feed_types.feed)) AS lang_type
           ON (user_feeds.feed=lang_type.url)
     WHERE user_feeds."public"=true
  GROUP BY "user"
  ORDER BY "user" ASC;

CREATE OR REPLACE VIEW directory AS
    SELECT users.name AS "user",
           COALESCE(users.title, users.name) As title,
           users.image,
           user_feeds.slug,
           COALESCE(user_feeds.title, feeds.title) AS feed_title,
           feeds.lang,
           feed_types.types
      FROM users
      JOIN user_feeds ON (users.name=user_feeds."user")
      JOIN feeds ON (user_feeds.feed=feeds.url)
      JOIN (SELECT "feed", array_agg("type") AS types
              FROM feed_types
          GROUP BY "feed"
           ) AS feed_types ON (user_feeds.feed=feed_types.feed)
     WHERE user_feeds."public"=true
  ORDER BY users.name ASC, user_feeds.slug ASC;
