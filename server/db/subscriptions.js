'use strict'
// 3rd
const assert = require('better-assert')
const debug = require('debug')('app:db:subscriptions')
// 1st
const { pool } = require('./util')
const { sql } = require('pg-extra')
const db = require('.')

////////////////////////////////////////////////////////////

// Gets non-archived subs
exports.listActiveSubscribersForTopic = async function(topicId) {
    assert(Number.isInteger(topicId))

    return pool.many(sql`
    SELECT
      u.id
    FROM users u
    JOIN topic_subscriptions ts ON u.id = ts.user_id
    WHERE ts.topic_id = ${topicId}
      AND ts.is_archived = false
  `)
}

////////////////////////////////////////////////////////////

// Sort them by latest_posts first
exports.findSubscribedTopicsForUserId = async function(userId, isArchived) {
    assert(Number.isInteger(userId))
    assert(typeof isArchived === 'boolean')

    return pool.many(sql`
SELECT
  t.*,
  json_build_object(
    'uname', u.uname,
    'slug', u.slug
  ) "user",

  json_build_object(
    'id', latest_post.id,
    'created_at', latest_post.created_at
  ) "latest_post",

  json_build_object(
    'uname', u2.uname,
    'slug', u2.slug
  ) "latest_user",

  CASE
    WHEN latest_ic_post IS NULL THEN NULL
    ELSE
      json_build_object(
        'id', latest_ic_post.id,
        'created_at', latest_ic_post.created_at
      )
  END "latest_ic_post",

  CASE
    WHEN latest_ic_user IS NULL THEN NULL
    ELSE
      json_build_object(
        'uname', latest_ic_user.uname,
        'slug', latest_ic_user.slug
      )
  END "latest_ic_user",

  CASE
    WHEN latest_ooc_post IS NULL THEN NULL
    ELSE
      json_build_object(
        'id', latest_ooc_post.id,
        'created_at', latest_ooc_post.created_at
      )
  END "latest_ooc_post",

  CASE
    WHEN latest_ooc_user IS NULL THEN NULL
    ELSE
      json_build_object(
        'uname', latest_ooc_user.uname,
        'slug', latest_ooc_user.slug
      )
  END "latest_ooc_user",

  CASE
    WHEN latest_char_post IS NULL THEN NULL
    ELSE
      json_build_object(
        'id', latest_char_post.id,
        'created_at', latest_char_post.created_at
      )
  END "latest_char_post",

  CASE
    WHEN latest_char_user IS NULL THEN NULL
    ELSE
      json_build_object(
        'uname', latest_char_user.uname,
        'slug', latest_char_user.slug
      )
  END "latest_char_user",

  to_json(f.*) "forum",
  ts.is_archived
FROM topic_subscriptions ts
JOIN topics t ON ts.topic_id = t.id
JOIN users u ON t.user_id = u.id
LEFT OUTER JOIN posts latest_post ON t.latest_post_id = latest_post.id
LEFT OUTER JOIN posts latest_ic_post ON t.latest_ic_post_id = latest_ic_post.id
LEFT OUTER JOIN users latest_ic_user ON latest_ic_post.user_id = latest_ic_user.id
LEFT OUTER JOIN posts latest_ooc_post ON t.latest_ooc_post_id = latest_ooc_post.id
LEFT OUTER JOIN users latest_ooc_user ON latest_ooc_post.user_id = latest_ooc_user.id
LEFT OUTER JOIN posts latest_char_post ON t.latest_char_post_id = latest_char_post.id
LEFT OUTER JOIN users latest_char_user ON latest_char_post.user_id = latest_char_user.id
JOIN users u2 ON latest_post.user_id = u2.id
JOIN forums f ON t.forum_id = f.id
WHERE ts.user_id = ${userId}
  AND is_archived = ${isArchived}
ORDER BY t.latest_post_id DESC
  `)
}

////////////////////////////////////////////////////////////

// Do nothing if subscription already exists
exports.subscribeToTopic = async function(userId, topicId) {
    assert(userId)
    assert(topicId)
    return pool.query(sql`
    INSERT INTO topic_subscriptions (user_id, topic_id)
    VALUES (${userId}, ${topicId})
    ON CONFLICT (user_id, topic_id) DO NOTHING
  `)
}

////////////////////////////////////////////////////////////

// unsub/archive should delete any existing notifications
exports.massUpdate = async function(userId, topicIds, action) {
    assert(['unsub', 'archive', 'unarchive'].includes(action))

    if (action === 'archive') {
        return Promise.all([
            pool.query(sql`
        UPDATE topic_subscriptions
        SET is_archived = true
        WHERE topic_id = ANY (${topicIds})
          AND user_id = ${userId}
        RETURNING *
      `),
            db.deleteSubNotifications(userId, topicIds),
        ])
    }

    if (action === 'unsub') {
        return Promise.all([
            pool.query(sql`
        DELETE FROM topic_subscriptions
        WHERE topic_id = ANY (${topicIds})
          AND user_id = ${userId}
      `),
            db.deleteSubNotifications(userId, topicIds),
        ])
    }

    if (action === 'unarchive') {
        return pool.query(sql`
      UPDATE topic_subscriptions
      SET is_archived = false
      WHERE topic_id = ANY (${topicIds})
        AND user_id = ${userId}
      RETURNING *
    `)
    }

    assert(false)
}

////////////////////////////////////////////////////////////

// Delete any existing notifications for topic
exports.unsubscribeFromTopic = async function(userId, topicId) {
    return Promise.all([
        pool.query(sql`
      DELETE FROM topic_subscriptions
      WHERE user_id = ${userId} AND topic_id = ${topicId}
    `),
        db.deleteSubNotifications(userId, [topicId]),
    ])
}
