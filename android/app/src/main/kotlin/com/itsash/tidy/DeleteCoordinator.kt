package com.itsash.tidy

import android.app.Activity
import android.app.RecoverableSecurityException
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.TimeUnit

/** A photo or video to remove. */
data class MediaRef(val id: Long, val video: Boolean) {
    val uri: Uri get() = MediaRow.uriFor(id, video)

    /** Same as `MediaItem.key` in Dart: photo and video ids can collide, so videos are negative. */
    val key: Long get() = if (video) -id - 1 else id
}

/**
 * Deletes media the way each Android version allows:
 *  - Android 11+: `MediaStore.createDeleteRequest` / `createTrashRequest`, one system dialog per
 *    chunk of [CHUNK] files; the result arrives in [onActivityResult].
 *  - Android 10 and below: `ContentResolver.delete` per file; a `RecoverableSecurityException`
 *    (Android 10, file owned by another app) asks the user for that file and retries once.
 * The Flutter result is `{deleted: [keys], cancelled: bool}` (see [MediaRef.key]).
 */
class DeleteCoordinator(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    // Android 11+ state, touched on the main thread only.
    private var chunks = ArrayDeque<List<MediaRef>>()
    private var currentChunk: List<MediaRef> = emptyList()
    private val deleted = ArrayList<Long>()
    private var trash = false
    private var result: MethodChannel.Result? = null

    // Android 10 and below: the worker waits here for the user's answer.
    private val legacyAnswer = SynchronousQueue<Int>()

    val busy: Boolean get() = result != null

    fun delete(items: List<MediaRef>, trash: Boolean, result: MethodChannel.Result) {
        if (busy) return result.error("busy", "A delete is already running.", null)
        if (items.isEmpty()) return result.success(mapOf("deleted" to emptyList<Long>(), "cancelled" to false))
        this.result = result
        deleted.clear()
        if (Build.VERSION.SDK_INT >= 30) {
            this.trash = trash
            chunks = ArrayDeque(items.chunked(CHUNK))
            nextChunk()
        } else {
            worker.execute { deleteLegacy(items) }
        }
    }

    /** Returns true when the request code belongs to Tidy. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        when (requestCode) {
            REQ_BATCH -> {
                if (resultCode == Activity.RESULT_OK) {
                    deleted.addAll(currentChunk.map { it.key })
                    nextChunk()
                } else {
                    finish(cancelled = true)
                }
            }
            REQ_LEGACY -> legacyAnswer.offer(resultCode, 1, TimeUnit.SECONDS)
            else -> return false
        }
        return true
    }

    private fun nextChunk() {
        val chunk = chunks.removeFirstOrNull() ?: return finish(cancelled = false)
        currentChunk = chunk
        try {
            val resolver = activity.contentResolver
            val uris = chunk.map { it.uri }
            val request = if (trash) MediaStore.createTrashRequest(resolver, uris, true) else MediaStore.createDeleteRequest(resolver, uris)
            activity.startIntentSenderForResult(request.intentSender, REQ_BATCH, null, 0, 0, 0)
        } catch (e: Exception) {
            fail(e)
        }
    }

    private fun deleteLegacy(items: List<MediaRef>) {
        val resolver = activity.contentResolver
        val done = ArrayList<Long>()
        var cancelled = false
        for (item in items) {
            try {
                if (tryDelete(resolver, item)) done.add(item.key)
            } catch (e: RecoverableSecurityException) {
                main.post {
                    try {
                        activity.startIntentSenderForResult(e.userAction.actionIntent.intentSender, REQ_LEGACY, null, 0, 0, 0)
                    } catch (_: Exception) {
                        legacyAnswer.offer(Activity.RESULT_CANCELED, 1, TimeUnit.SECONDS)
                    }
                }
                val answer = legacyAnswer.poll(10, TimeUnit.MINUTES)
                if (answer == Activity.RESULT_OK && runCatching { tryDelete(resolver, item) }.getOrDefault(false)) {
                    done.add(item.key)
                } else if (answer != Activity.RESULT_OK) {
                    cancelled = true
                    break
                }
            } catch (_: SecurityException) {
                // Not allowed to delete this one: skip it.
            }
        }
        main.post { deleted.addAll(done); finish(cancelled) }
    }

    private fun tryDelete(resolver: android.content.ContentResolver, item: MediaRef): Boolean =
        resolver.delete(item.uri, null, null) > 0

    private fun finish(cancelled: Boolean) {
        val r = result ?: return
        result = null
        r.success(mapOf("deleted" to ArrayList(deleted), "cancelled" to cancelled))
    }

    private fun fail(e: Exception) {
        val r = result ?: return
        result = null
        r.error("delete_failed", e.message, null)
    }

    private companion object {
        const val REQ_BATCH = 4101
        const val REQ_LEGACY = 4102
        const val CHUNK = 1000
    }
}
