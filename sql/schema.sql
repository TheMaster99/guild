DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

--
-- Only put things in this file that should be present for the
-- COPY FROM migration.
--

CREATE EXTENSION IF NOT EXISTS plv8;

CREATE TYPE role_type AS ENUM ('admin', 'smod', 'mod', 'member', 'banned');
ALTER TYPE role_type ADD VALUE 'conmod';

CREATE TABLE users (
  id             serial PRIMARY KEY,
  uname          text   NOT NULL,  -- Unique index added later in schema
  digest         text   NOT NULL,
  email          text   NOT NULL,  -- Unique index added later in schema
  oldguild_uname text   NULL,
  created_at     timestamp with time zone NOT NULL  DEFAULT NOW(),
  last_online_at timestamp with time zone NULL,
  is_ghost       boolean   NOT NULL  DEFAULT false,
  role           role_type NOT NULL  DEFAULT 'member',
  slug           text      NOT NULL,
  custom_title   text      NOT NULL  DEFAULT '',
  trophy_count   int       NOT NULL  DEFAULT 0,
  current_status_id int    NULL REFERENCES statuses(id) ON DELETE SET NULL,
  -- Cache
  posts_count    int       NOT NULL  DEFAULT 0,
  pms_count      int       NOT NULL  DEFAULT 0,
  sig            text      NOT NULL  DEFAULT '',
  legacy_sig     text      NULL,
  sig_html       text      NOT NULL  DEFAULT '',
  avatar_url     text      NOT NULL DEFAULT '',
  hide_sigs      boolean   NOT NULL  DEFAULT false,
  is_grayscale   boolean   NOT NULL  DEFAULT false,
  force_device_width boolean NOT NULL DEFAULT true,
  hide_avatars   boolean   NOT NULL  DEFAULT false,
  -- Bio
  bio_markup     text      NULL,
  bio_html       text      NULL,
  -- Notifications
  notifications_count         int NOT NULL  DEFAULT 0,
  convo_notifications_count   int NOT NULL  DEFAULT 0,
  mention_notifications_count int NOT NULL  DEFAULT 0,
  quote_notifications_count   int NOT NULL  DEFAULT 0
);

CREATE UNIQUE INDEX unique_username ON users USING btree (lower(uname));
CREATE UNIQUE INDEX unique_email ON users USING btree (lower(email));
CREATE UNIQUE INDEX unique_slug ON users USING btree (lower(slug));

CREATE TABLE reset_tokens (
  user_id int  NOT NULL  REFERENCES users(id)  ON DELETE CASCADE,
  token   uuid NOT NULL,
  created_at timestamp with time zone NOT NULL  DEFAULT NOW(),
  expired_at timestamp with time zone NOT NULL  DEFAULT NOW() + INTERVAL '15 minutes'
);

CREATE TABLE sessions (
  id         uuid PRIMARY KEY,
  user_id    int  REFERENCES users(id) ON DELETE CASCADE,
  ip_address inet NOT NULL,
  expired_at timestamp with time zone NOT NULL
                                      DEFAULT NOW() + INTERVAL '1 day',
  created_at timestamp with time zone NOT NULL  DEFAULT NOW()
);

CREATE VIEW active_sessions AS
  SELECT *
  FROM sessions
  WHERE expired_at >= NOW()
;

CREATE VIEW active_reset_tokens AS
  SELECT *
  FROM reset_tokens
  WHERE expired_at >= NOW()
;

CREATE TABLE categories (
  id          serial PRIMARY KEY,
  title       text NOT NULL,
  description text NULL,
  pos         int NOT NULL
);

CREATE TABLE forums (
  id              serial PRIMARY KEY,
  category_id     int NOT NULL  REFERENCES categories(id)  ON DELETE CASCADE,
  parent_forum_id int NULL  REFERENCES forums(id)  ON DELETE SET NULL,
  title           text NOT NULL,
  description     text NULL,
  pos             int NOT NULL,
  is_roleplay     boolean NOT NULL  DEFAULT false,
  tag_id          int NULL REFERENCES tags(id) ON DELETE SET NULL,
  has_tags_enabled boolean NOT NULL DEFAULT false,
  tab_title       text NULL,
  is_check        boolean NOT NULL DEFAULT false,
  -- Cache
  topics_count    int NOT NULL  DEFAULT 0,
  posts_count     int NOT NULL  DEFAULT 0
);

--
-- Topics/Posts system
--

CREATE TYPE join_status AS ENUM ('jump-in', 'apply', 'full');

CREATE TABLE topics (
  id         serial PRIMARY KEY,
  title      text NOT NULL,
  user_id    int NOT NULL  REFERENCES users(id)  ON DELETE CASCADE,
  forum_id   int NOT NULL  REFERENCES forums(id)  ON DELETE CASCADE,
  created_at timestamp with time zone NOT NULL  DEFAULT NOW(),
  is_roleplay boolean NOT NULL,
  co_gm_ids  int[] NOT NULL DEFAULT ARRAY[]::int[],
  join_status join_status NULL,
  -- Modkit flags
  is_hidden  boolean NOT NULL  DEFAULT false,
  is_closed  boolean NOT NULL  DEFAULT false,
  is_sticky  boolean NOT NULL  DEFAULT false,
  -- Counter Cache
  posts_count int NOT NULL  DEFAULT 0,
  ic_posts_count int NOT NULL DEFAULT 0,
  ooc_posts_count int NOT NULL DEFAULT 0,
  char_posts_count int NOT NULL DEFAULT 0,
  -- Moving
  moved_from_forum_id int NULL REFERENCES forums(id),
  moved_at timestamp with time zone NULL,
  latest_post_at timestamp with time zone NULL
);

CREATE TYPE post_type AS ENUM ('ic', 'ooc', 'char');

CREATE TABLE posts (
  id         serial PRIMARY KEY,
  text       text NULL,  -- Deprecated
  markup     text NULL,
  html       text NULL,  -- The rendered post.markup
  legacy_html text NULL,  -- Deprecated
  topic_id   int NOT NULL  REFERENCES topics(id)  ON DELETE CASCADE,
  user_id    int NOT NULL  REFERENCES users(id)  ON DELETE CASCADE,
  created_at timestamp with time zone NOT NULL  DEFAULT NOW(),
  updated_at timestamp with time zone NULL,
  is_roleplay boolean NOT NULL,
  type       post_type NOT NULL,
  ip_address inet NULL,
  is_hidden  boolean NOT NULL  DEFAULT false,
  idx         int  NULL
);

CREATE INDEX ON posts (ip_address);
-- TODO: Remove DESC from following idx column:
CREATE UNIQUE INDEX posts_topic_id_type_idx_idx ON posts (topic_id, type, idx DESC);

-- Last post cache
ALTER TABLE forums ADD COLUMN latest_post_id
  int NULL REFERENCES posts(id)  ON DELETE SET NULL;
ALTER TABLE topics ADD COLUMN latest_post_id
  int NULL REFERENCES posts(id)  ON DELETE SET NULL;
ALTER TABLE topics ADD COLUMN latest_ic_post_id
  int NULL REFERENCES posts(id)  ON DELETE SET NULL;
ALTER TABLE topics ADD COLUMN latest_ooc_post_id
  int NULL REFERENCES posts(id)  ON DELETE SET NULL;
ALTER TABLE topics ADD COLUMN latest_char_post_id
  int NULL REFERENCES posts(id)  ON DELETE SET NULL;

CREATE TABLE topic_subscriptions (
  user_id int NOT NULL  REFERENCES users(id)  ON DELETE CASCADE,
  topic_id int NOT NULL  REFERENCES topics(id)  ON DELETE CASCADE,
  UNIQUE (user_id, topic_id)
);

--
-- Convos/Private-messaging system
--

CREATE TABLE convos (
  id          serial PRIMARY KEY,
  user_id     int    NOT NULL  REFERENCES users(id) ON DELETE CASCADE,
  created_at  timestamp with time zone NOT NULL  DEFAULT NOW(),
  title       text   NOT NULL,
  is_archived boolean NOT NULL  DEFAULT false,
  legacy_participant_ids integer[] NULL,
  -- Cache
  pms_count int    NOT NULL  DEFAULT 0
);

CREATE TABLE pms (
  id         serial PRIMARY KEY,
  text       text   NULL,  -- Deprecated
  markup     text   NULL,
  html       text   NULL,
  legacy_html text NULL,  -- Deprecated
  convo_id   int    NOT NULL  REFERENCES convos(id)  ON DELETE CASCADE,
  user_id    int    NOT NULL  REFERENCES users(id)  ON DELETE CASCADE,
  ip_address inet   NULL,
  idx        int    NOT NULL,
  created_at timestamp with time zone NOT NULL  DEFAULT NOW(),
  updated_at timestamp with time zone NULL
);

CREATE INDEX ON pms (ip_address);

-- Latest PM cache
ALTER TABLE convos ADD COLUMN latest_pm_id
  int NULL REFERENCES pms(id)  ON DELETE SET NULL;

CREATE UNIQUE INDEX pms_convo_id_idx_idx ON pms (convo_id, idx DESC);

CREATE TABLE convos_participants (
  convo_id int NOT NULL  REFERENCES convos(id) ON DELETE CASCADE,
  user_id  int NOT NULL  REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (user_id, convo_id)
);

--
-- Notifications
--

CREATE TYPE notification_type AS ENUM ('MENTION', 'QUOTE', 'CONVO', 'RATING');

CREATE TABLE notifications (
  id           serial PRIMARY KEY,
  type         notification_type NOT NULL,
  from_user_id int NOT NULL  REFERENCES users(id),
  to_user_id   int NOT NULL  REFERENCES users(id),
  created_at   timestamp with time zone NOT NULL  DEFAULT NOW(),
  count        int NULL,
  --
  convo_id int NULL  REFERENCES convos(id) ON DELETE CASCADE,
  pm_id    int NULL  REFERENCES pms(id) ON DELETE CASCADE,
  topic_id int NULL  REFERENCES topics(id) ON DELETE CASCADE,
  post_id  int NULL  REFERENCES posts(id) ON DELETE CASCADE,
  meta     json NULL,
  UNIQUE (to_user_id, convo_id)
);

--
-- Viewers tracking
--

CREATE TABLE viewers (
  -- uname is set when user is logged-in
  uname     text     NULL,
  -- ip is set when user is logged-out/guest
  ip        inet     NULL,
  forum_id  int      NOT NULL,
  topic_id  int      NULL,
  viewed_at timestamp with time zone NOT NULL  DEFAULT NOW(),
  UNIQUE (uname),
  UNIQUE (ip),
  -- Ensure either uname or ip is set
  CHECK(
    (CASE WHEN uname IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN ip IS NOT NULL THEN 1 ELSE 0 END)
    = 1
  )
);

CREATE INDEX viewers_forum_id ON viewers (forum_id);
CREATE INDEX viewers_topic_id ON viewers (topic_id);

-- Always select from this.
-- A cronjob will delete expired views, but this lets us run the cronjob
-- much less frequently. (i.e. limited by Heroku Scheduler's min interval)
CREATE VIEW active_viewers AS
  SELECT *
  FROM viewers
  WHERE viewed_at > NOW() - interval '15 minutes'
;

--
-- Post ratings
--

CREATE TYPE rating_type AS ENUM ('like', 'laugh', 'thank');

CREATE TABLE ratings (
  from_user_id    int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_user_uname text NOT NULL,
  to_user_id      int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id         int NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  type            rating_type NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT NOW(),
  -- A user can rate a post once
  UNIQUE(from_user_id, post_id)
);

--
-- Topic tags
--

CREATE TABLE tag_groups (
  id serial PRIMARY KEY,
  title text NOT NULL,
  -- Constraints
  UNIQUE(title)
);

CREATE TABLE tags (
  id serial PRIMARY KEY,
  tag_group_id int NOT NULL REFERENCES tag_groups(id),
  title text NOT NULL,
  description text NULL,
  created_at timestamp with time zone NOT NULL DEFAULT NOW(),
  -- Constraints
  UNIQUE(title)
);

CREATE INDEX ON tags (tag_group_id);

CREATE TABLE tags_topics (
  topic_id int NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  tag_id   int NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  -- Constraints
  UNIQUE(topic_id, tag_id)
);

-- FK lookups
CREATE INDEX ON tags_topics (topic_id);
CREATE INDEX ON tags_topics (tag_id);

--
-- Trophies
--

CREATE TABLE trophy_groups (
  id         serial PRIMARY KEY,
  title      text NOT NULL,
  description_markup     text NULL,
  description_html       text NULL,
  created_at timestamp with time zone NOT NULL DEFAULT NOW()
);

CREATE TABLE trophies (
  id       serial PRIMARY KEY,
  group_id int NULL REFERENCES trophy_groups(id) ON DELETE CASCADE,
  title    text NOT NULL,
  -- awarded_count is the number of times this trophy has been awarded
  awarded_count int NOT NULL DEFAULT 0,
  -- description is BBCode markup
  description_markup text NULL,
  description_html   text NULL,
  image_url   text NULL,
  -- [width, height]
  image_dims  int[] NULL,
  created_at  timestamp with time zone NOT NULL DEFAULT NOW()
);

-- When set, it's the description of the effect when activated.
-- If null, then trophie has no special effect when activated.
ALTER TABLE trophies
ADD COLUMN special_effect text NULL;

ALTER TABLE users
ADD COLUMN active_trophy_id int NULL REFERENCES trophies(id);

-- FK indexes
CREATE INDEX trophies__group_id ON trophies (group_id);

CREATE TABLE trophies_users (
  user_id    int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trophy_id  int NOT NULL REFERENCES trophies(id) ON DELETE CASCADE,
  awarded_at timestamp with time zone NOT NULL DEFAULT NOW(),
  awarded_by int NULL REFERENCES users(id) ON DELETE CASCADE,
  -- n represents that this user was the awardee of this trophy
  -- i.e. n of 42 means this is the 42nd awarding of this trophy
  n          int NOT NULL DEFAULT 0,
  -- message is BBCode that describes more info about
  -- this specific awarding. Perhaps it links to the topic/post
  -- that the receiver was awarded for. etc.
  message_markup    text NULL,
  message_html      text NULL,
  -- Constraints
  UNIQUE(trophy_id, n)
);

-- is recipient anonymous?
ALTER TABLE trophies_users
ADD COLUMN is_anon boolean NOT NULL DEFAULT false;

-- FK indexes
CREATE INDEX trophies_users__user_id ON trophies_users (user_id);
CREATE INDEX trophies_users__awarded_by ON trophies_users (awarded_by);
CREATE INDEX trophies_users__awarded_at ON trophies_users (awarded_at);

------------------------------------------------------------
------------------------------------------------------------
-- Functions/triggers that should exist for the COPY FROM
-- migration. Everything else should be in
-- functions_and_triggers.sql
------------------------------------------------------------
------------------------------------------------------------
-- Set post idx before inserted

CREATE OR REPLACE FUNCTION set_post_idx() RETURNS trigger AS
$$
  q = 'SELECT COALESCE(MAX(p.idx) + 1, 0) "idx"  '+
      'FROM posts p                              '+
      'WHERE p.topic_id = $1 AND p.type = $2     ';
  var rows = plv8.execute(q, [NEW.topic_id, NEW.type]);
  NEW.idx = rows[0].idx;
  return NEW;
$$ LANGUAGE 'plv8';

DROP TRIGGER IF EXISTS trigger_set_post_idx ON posts;
CREATE TRIGGER trigger_set_post_idx
    BEFORE INSERT ON posts
    FOR EACH ROW
    EXECUTE PROCEDURE set_post_idx();

------------------------------------------------------------
------------------------------------------------------------
-- Set pm idx before insertion

CREATE OR REPLACE FUNCTION set_pm_idx() RETURNS trigger AS
$$
  q = 'SELECT COALESCE(MAX(pms.idx) + 1, 0) "idx"  '+
      'FROM pms                                    '+
      'WHERE pms.convo_id = $1                     ';
  var rows = plv8.execute(q, [NEW.convo_id]);
  NEW.idx = rows[0].idx;
  return NEW;
$$ LANGUAGE 'plv8';

DROP TRIGGER IF EXISTS trigger_set_pm_idx ON pms;
CREATE TRIGGER trigger_set_pm_idx
    BEFORE INSERT ON pms
    FOR EACH ROW
    EXECUTE PROCEDURE set_pm_idx();

------------------------------------------------------------
------------------------------------------------------------

-- User statuses

CREATE TABLE statuses (
  id          serial PRIMARY KEY,
  user_id     int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text        text NOT NULL,
  html        text NOT NULL,
  liked_user_ids int[] NOT NULL DEFAULT array[]::int[],
  created_at  timestamp with time zone NOT NULL DEFAULT NOW()
);

-- To quickly find statuses written by a user
CREATE INDEX statuses__user_id ON statuses (user_id);
-- To quickly find the latest X statuses sorted by created_at
CREATE INDEX statuses__created_at ON statuses (created_at);

------------------------------------------------------------

CREATE TABLE status_likes (
  status_id   int NOT NULL REFERENCES statuses(id) ON DELETE CASCADE,
  user_id     int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  timestamp with time zone NOT NULL DEFAULT NOW(),
  -- Constraints
  -- A user can only like a status once
  UNIQUE(status_id, user_id)
);

-- To quickly find latest liked status (created_at) for a user_id
CREATE INDEX statuses_likes__created_at ON status_likes (created_at);

------------------------------------------------------------

CREATE TABLE topics_users_watermark (
  topic_id          int NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  user_id           int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  watermark_post_id int NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  post_type         post_type NOT NULL,
  -- User can only have a watermark for each post_type in each topic
  UNIQUE(topic_id, user_id, post_type)
);

-- Quickly fetch max watermark
CREATE INDEX topics_users_watermark__watermark_post_id
  ON topics_users_watermark (watermark_post_id);


------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------

-- Friendships are really just one-way.
-- Consider changing this table name to 'stalkings'
CREATE TABLE friendships (
  id           serial PRIMARY KEY,
  from_user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id   integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   timestamp with time zone NOT NULL DEFAULT NOW(),
  -- Only one link may exist between two users
  UNIQUE (from_user_id, to_user_id),
  -- user cannot befriend themself
  CHECK (from_user_id != to_user_id)
);

CREATE INDEX ON friendships (from_user_id);
CREATE INDEX ON friendships (to_user_id);

------------------------------------------------------------

CREATE TABLE chat_mutes (
  id serial PRIMARY KEY,
  user_id integer NOT NULL REFERENCES users(id),
  expires_at timestamp with time zone NULL,
  created_at timestamp with time zone NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX ON chat_mutes (user_id);

------------------------------------------------------------

CREATE TABLE chat_messages (
  id         serial PRIMARY KEY,
  -- System messages do not have a user
  user_id    integer NULL REFERENCES users(id),
  text       text    NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT NOW()
);

CREATE INDEX ON chat_messages (user_id);
