package com.itsash.tidy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Size

/** Small bitmaps for photos and videos, for the grid and for analysis. */
object Thumbnails {
    /** Longest side [side] px, or null when the file cannot be decoded. */
    fun load(context: Context, row: MediaRow, side: Int): Bitmap? = load(context, row.id, row.video, side)

    fun load(context: Context, id: Long, video: Boolean, side: Int): Bitmap? {
        val uri = MediaRow.uriFor(id, video)
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                return softwareCopy(context.contentResolver.loadThumbnail(uri, Size(side, side), null))
            } catch (_: Exception) {
                // Fall through to decoding the file ourselves.
            }
        }
        return try {
            if (video) videoFrame(context, uri, side) else decodeImage(context, uri, side)
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    private fun decodeImage(context: Context, uri: android.net.Uri, side: Int): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openFileDescriptor(uri, "r")?.use { BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= side) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return resolver.openFileDescriptor(uri, "r")?.use { BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, opts) }
    }

    private fun videoFrame(context: Context, uri: android.net.Uri, side: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val frame = retriever.getFrameAtTime(-1) ?: return null
            val (w, h) = ImageMetrics.fit(frame.width, frame.height, side)
            if (w == frame.width && h == frame.height) frame else Bitmap.createScaledBitmap(frame, w, h, true)
        } finally {
            retriever.release()
        }
    }

    private fun softwareCopy(bmp: Bitmap): Bitmap =
        if (bmp.config == Bitmap.Config.HARDWARE) bmp.copy(Bitmap.Config.ARGB_8888, false) else bmp

    /** dHash and blur score of [bmp], computed on a grayscale copy of at most 256 px. */
    fun analyze(bmp: Bitmap): Pair<Long, Double> {
        val (w, h) = ImageMetrics.fit(bmp.width, bmp.height)
        val scaled = if (w == bmp.width && h == bmp.height) bmp else Bitmap.createScaledBitmap(bmp, w, h, true)
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        if (scaled !== bmp) scaled.recycle()
        val gray = ImageMetrics.toGray(pixels)
        return ImageMetrics.dHash(gray, w, h) to ImageMetrics.blurScore(gray, w, h)
    }
}
