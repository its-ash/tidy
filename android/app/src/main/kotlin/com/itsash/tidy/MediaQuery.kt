package com.itsash.tidy

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

/** One photo or video from MediaStore. Times: [added] and [modified] in seconds, [taken] in ms. */
data class MediaRow(
    val id: Long,
    val video: Boolean,
    val path: String,
    val bucket: String,
    val size: Long,
    val added: Long,
    val modified: Long,
    val taken: Long,
    val width: Int,
    val height: Int,
    val durationMs: Long,
    val mime: String,
) {
    fun uri(): Uri = uriFor(id, video)

    fun toMap(dHash: Long?, blur: Double?, fullHash: String?): Map<String, Any?> = mapOf(
        "id" to id, "video" to video, "path" to path, "bucket" to bucket, "size" to size,
        "added" to added, "modified" to modified, "taken" to taken, "width" to width,
        "height" to height, "duration" to durationMs, "mime" to mime,
        "dhash" to dHash, "blur" to blur, "hash" to fullHash,
    )

    companion object {
        fun uriFor(id: Long, video: Boolean): Uri = ContentUris.withAppendedId(
            if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            id,
        )
    }
}

/** Reads every image and video row from MediaStore in one query. */
object MediaQuery {
    private val required = arrayOf(
        MediaStore.Files.FileColumns._ID,
        MediaStore.Files.FileColumns.MEDIA_TYPE,
        MediaStore.MediaColumns.DATA,
        MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.DATE_ADDED,
        MediaStore.MediaColumns.DATE_MODIFIED,
        MediaStore.MediaColumns.MIME_TYPE,
    )

    // Columns that older Android versions may not expose on the Files table.
    private val optional = arrayOf(
        MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
        MediaStore.MediaColumns.WIDTH,
        MediaStore.MediaColumns.HEIGHT,
        "datetaken",
        "duration",
    )

    private const val SELECTION =
        "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, " +
            "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}) AND ${MediaStore.MediaColumns.SIZE} > 0"

    fun list(context: Context): List<MediaRow> {
        val uri = MediaStore.Files.getContentUri(if (Build.VERSION.SDK_INT >= 29) MediaStore.VOLUME_EXTERNAL else "external")
        return try {
            query(context, uri, required + optional)
        } catch (e: Exception) {
            query(context, uri, required)
        }
    }

    private fun query(context: Context, uri: Uri, projection: Array<String>): List<MediaRow> {
        val out = ArrayList<MediaRow>()
        context.contentResolver.query(uri, projection, SELECTION, null, null)?.use { c ->
            fun col(name: String) = c.getColumnIndex(name)
            val iId = col(MediaStore.Files.FileColumns._ID)
            val iType = col(MediaStore.Files.FileColumns.MEDIA_TYPE)
            val iData = col(MediaStore.MediaColumns.DATA)
            val iSize = col(MediaStore.MediaColumns.SIZE)
            val iAdded = col(MediaStore.MediaColumns.DATE_ADDED)
            val iModified = col(MediaStore.MediaColumns.DATE_MODIFIED)
            val iMime = col(MediaStore.MediaColumns.MIME_TYPE)
            val iBucket = col(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
            val iW = col(MediaStore.MediaColumns.WIDTH)
            val iH = col(MediaStore.MediaColumns.HEIGHT)
            val iTaken = col("datetaken")
            val iDur = col("duration")
            fun long(i: Int) = if (i >= 0 && !c.isNull(i)) c.getLong(i) else 0L
            fun str(i: Int) = if (i >= 0 && !c.isNull(i)) c.getString(i) else ""
            while (c.moveToNext()) {
                val modified = long(iModified)
                val taken = long(iTaken).takeIf { it > 0 } ?: (modified * 1000)
                out.add(
                    MediaRow(
                        id = c.getLong(iId),
                        video = c.getInt(iType) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO,
                        path = str(iData),
                        bucket = str(iBucket),
                        size = long(iSize),
                        added = long(iAdded),
                        modified = modified,
                        taken = taken,
                        width = long(iW).toInt(),
                        height = long(iH).toInt(),
                        durationMs = long(iDur),
                        mime = str(iMime),
                    ),
                )
            }
        }
        return out
    }
}
