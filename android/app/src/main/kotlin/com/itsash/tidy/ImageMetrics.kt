package com.itsash.tidy

/**
 * Pure image maths on grayscale pixels (row-major, 0..255). No Android classes, so it is
 * unit-tested on the JVM (see `src/test`).
 */
object ImageMetrics {
    /** Grid used by [dHash]: 9 columns x 8 rows gives 8 comparisons per row = 64 bits. */
    private const val HASH_COLS = 9
    private const val HASH_ROWS = 8

    /** Longest side of the grayscale image the metrics are computed on. */
    const val ANALYSIS_SIDE = 256

    /** Luma (Rec. 601) of packed ARGB pixels. */
    fun toGray(argb: IntArray): IntArray = IntArray(argb.size) {
        val p = argb[it]
        (((p shr 16) and 0xFF) * 299 + ((p shr 8) and 0xFF) * 587 + (p and 0xFF) * 114) / 1000
    }

    /**
     * 64-bit difference hash. The image is box-averaged to 9x8 cells and each bit says whether a
     * cell is brighter than its right neighbour. Robust to resizing, re-compression and brightness
     * shifts; similar photos differ in only a few bits (Hamming distance).
     */
    fun dHash(gray: IntArray, w: Int, h: Int): Long {
        require(w >= HASH_COLS && h >= HASH_ROWS) { "image too small: ${w}x$h" }
        val cells = DoubleArray(HASH_COLS * HASH_ROWS)
        for (cy in 0 until HASH_ROWS) {
            val y0 = cy * h / HASH_ROWS
            val y1 = maxOf(y0 + 1, (cy + 1) * h / HASH_ROWS)
            for (cx in 0 until HASH_COLS) {
                val x0 = cx * w / HASH_COLS
                val x1 = maxOf(x0 + 1, (cx + 1) * w / HASH_COLS)
                var sum = 0L
                for (y in y0 until y1) for (x in x0 until x1) sum += gray[y * w + x]
                cells[cy * HASH_COLS + cx] = sum.toDouble() / ((y1 - y0) * (x1 - x0))
            }
        }
        var hash = 0L
        for (y in 0 until HASH_ROWS) {
            for (x in 0 until HASH_COLS - 1) {
                hash = hash shl 1
                if (cells[y * HASH_COLS + x] > cells[y * HASH_COLS + x + 1]) hash = hash or 1L
            }
        }
        return hash
    }

    /**
     * Variance of the 3x3 Laplacian: the classic sharpness measure. Sharp images have strong edges
     * and a large variance; blurred ones are smooth and score close to 0.
     */
    fun blurScore(gray: IntArray, w: Int, h: Int): Double {
        if (w < 3 || h < 3) return 0.0
        var sum = 0.0
        var sumSq = 0.0
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val i = y * w + x
                val lap = 4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - w] - gray[i + w]
                sum += lap
                sumSq += lap.toDouble() * lap
            }
        }
        val n = (w - 2).toDouble() * (h - 2)
        val mean = sum / n
        return sumSq / n - mean * mean
    }

    /** Size that fits [w] x [h] into [side] x [side], keeping the aspect ratio (never upscales). */
    fun fit(w: Int, h: Int, side: Int = ANALYSIS_SIDE): Pair<Int, Int> {
        val longest = maxOf(w, h)
        if (longest <= side) return w to h
        val scale = side.toDouble() / longest
        return maxOf(1, (w * scale).toInt()) to maxOf(1, (h * scale).toInt())
    }
}
