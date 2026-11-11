package com.itsash.tidy

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** What is remembered about one file. Valid while [modified] and [size] still match MediaStore. */
data class CachedMedia(
    val id: Long,
    val modified: Long,
    val size: Long,
    val dHash: Long?,
    val blur: Double?,
    val part: String?,
    val full: String?,
)

/**
 * Local SQLite cache keyed by MediaStore id + date_modified, so a rescan only analyses new or
 * changed files. Stores the dHash, the blur score and the duplicate-detection hashes.
 */
class AnalysisCache(context: Context) : SQLiteOpenHelper(context, "analysis.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE media (id INTEGER PRIMARY KEY, modified INTEGER NOT NULL, size INTEGER NOT NULL, " +
                "dhash INTEGER, blur REAL, part TEXT, full TEXT)",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /** All rows that still match [rows]; stale rows are deleted. */
    fun loadValid(rows: List<MediaRow>): MutableMap<Long, CachedMedia> {
        val live = HashMap<Long, MediaRow>(rows.size * 2)
        for (r in rows) live[r.id] = r
        val valid = HashMap<Long, CachedMedia>()
        val stale = ArrayList<Long>()
        readableDatabase.rawQuery("SELECT id, modified, size, dhash, blur, part, full FROM media", null).use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val row = live[id]
                if (row == null || row.modified != c.getLong(1) || row.size != c.getLong(2)) {
                    stale.add(id)
                    continue
                }
                valid[id] = CachedMedia(
                    id, c.getLong(1), c.getLong(2),
                    if (c.isNull(3)) null else c.getLong(3),
                    if (c.isNull(4)) null else c.getDouble(4),
                    c.getString(5), c.getString(6),
                )
            }
        }
        delete(stale)
        return valid
    }

    fun putAnalysis(batch: List<CachedMedia>) = inTransaction { db ->
        for (m in batch) {
            val v = ContentValues().apply {
                put("id", m.id); put("modified", m.modified); put("size", m.size)
                if (m.dHash == null) putNull("dhash") else put("dhash", m.dHash)
                if (m.blur == null) putNull("blur") else put("blur", m.blur)
                putNull("part"); putNull("full")
            }
            db.insertWithOnConflict("media", null, v, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    /** Sets the duplicate hashes of a file, creating the row when only the hashes are known. */
    fun putHashes(batch: List<CachedMedia>) = inTransaction { db ->
        for (m in batch) {
            val v = ContentValues().apply { put("part", m.part); put("full", m.full) }
            val updated = db.update("media", v, "id = ?", arrayOf(m.id.toString()))
            if (updated == 0) {
                v.put("id", m.id); v.put("modified", m.modified); v.put("size", m.size)
                db.insert("media", null, v)
            }
        }
    }

    fun delete(ids: List<Long>) {
        if (ids.isEmpty()) return
        inTransaction { db -> ids.forEach { db.delete("media", "id = ?", arrayOf(it.toString())) } }
    }

    fun clear() {
        writableDatabase.delete("media", null, null)
    }

    private inline fun inTransaction(block: (SQLiteDatabase) -> Unit) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            block(db)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}
