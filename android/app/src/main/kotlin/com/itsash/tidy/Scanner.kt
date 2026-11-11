package com.itsash.tidy

import android.content.Context
import java.io.FileInputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors

/** Progress of a scan. [phase] is `listing`, `analyzing` or `hashing`. */
data class ScanProgress(val phase: String, val done: Int, val total: Int)

/**
 * One scan: list MediaStore, analyse new or changed images (dHash + blur) and hash the files that
 * could be exact duplicates. Everything expensive is cached in [AnalysisCache].
 */
class Scanner(
    private val context: Context,
    private val cache: AnalysisCache,
    private val onProgress: (ScanProgress) -> Unit,
) {
    @Volatile private var cancelled = false
    private var lastEmit = 0L

    fun cancel() {
        cancelled = true
    }

    /** Returns one map per photo or video, in the shape documented in CLAUDE.md. */
    fun run(force: Boolean): List<Map<String, Any?>> {
        emit(ScanProgress("listing", 0, 0), always = true)
        val rows = MediaQuery.list(context)
        if (force) cache.clear()
        val known = cache.loadValid(rows)
        check()

        analyzeImages(rows, known)
        hashDuplicates(rows, known)

        return rows.map { r ->
            val c = known[r.id]
            r.toMap(c?.dHash, c?.blur, c?.full)
        }
    }

    private fun analyzeImages(rows: List<MediaRow>, known: MutableMap<Long, CachedMedia>) {
        val todo = rows.filter { !it.video && known[it.id] == null }
        var done = 0
        val batch = ArrayList<CachedMedia>()
        emit(ScanProgress("analyzing", 0, todo.size), always = true)
        parallel(todo, { row ->
            val bmp = Thumbnails.load(context, row, SIDE)
            bmp?.let { runCatching { Thumbnails.analyze(it) }.getOrNull() }
        }) { row, metrics ->
            val result = CachedMedia(row.id, row.modified, row.size, metrics?.first, metrics?.second, null, null)
            known[result.id] = result
            batch.add(result)
            if (batch.size >= 200) flush(batch) { cache.putAnalysis(it) }
            emit(ScanProgress("analyzing", ++done, todo.size))
        }
        flush(batch) { cache.putAnalysis(it) }
    }

    /**
     * Exact duplicates: same size, then same hash of size + first/last 64 KB, then same SHA-256
     * of the whole file. Each step only runs for files that collided in the previous one.
     */
    private fun hashDuplicates(rows: List<MediaRow>, known: MutableMap<Long, CachedMedia>) {
        val sameSize = rows.groupBy { it.size }.values.filter { it.size > 1 }.flatten()
        val needPart = sameSize.filter { known[it.id]?.part == null }
        var done = 0
        val batch = ArrayList<CachedMedia>()
        emit(ScanProgress("hashing", 0, needPart.size), always = true)
        parallel(needPart, { row -> withChannel(row) { ContentHash.partial(it, row.size) } }) { row, part ->
            val result = known[row.id].orEmpty(row).copy(part = part)
            known[result.id] = result
            batch.add(result)
            if (batch.size >= 200) flush(batch) { cache.putHashes(it) }
            emit(ScanProgress("hashing", ++done, needPart.size))
        }
        flush(batch) { cache.putHashes(it) }

        val candidates = sameSize
            .filter { known[it.id]?.part != null }
            .groupBy { it.size to known[it.id]?.part }.values
            .filter { it.size > 1 }.flatten()
        val needFull = candidates.filter { known[it.id]?.full == null }
        done = 0
        emit(ScanProgress("hashing", 0, needFull.size), always = true)
        parallel(needFull, { row -> withChannel(row) { ContentHash.full(it) { cancelled } } }) { row, full ->
            val result = known[row.id].orEmpty(row).copy(full = full)
            known[result.id] = result
            batch.add(result)
            if (batch.size >= 50) flush(batch) { cache.putHashes(it) }
            emit(ScanProgress("hashing", ++done, needFull.size))
        }
        flush(batch) { cache.putHashes(it) }
    }

    private fun CachedMedia?.orEmpty(row: MediaRow) =
        this ?: CachedMedia(row.id, row.modified, row.size, null, null, null, null)

    /** Opens the file read-only and runs [block]; null when it cannot be opened or read. */
    private fun <T> withChannel(row: MediaRow, block: (java.nio.channels.FileChannel) -> T?): T? = try {
        context.contentResolver.openFileDescriptor(row.uri(), "r")?.use { pfd ->
            FileInputStream(pfd.fileDescriptor).use { block(it.channel) }
        }
    } catch (_: Exception) {
        null
    }

    private fun flush(batch: MutableList<CachedMedia>, write: (List<CachedMedia>) -> Unit) {
        if (batch.isEmpty()) return
        write(batch.toList())
        batch.clear()
    }

    /** Runs [work] for every item on a small thread pool and feeds results to [onResult] on this thread. */
    private fun <T, R> parallel(items: List<T>, work: (T) -> R, onResult: (T, R) -> Unit) {
        if (items.isEmpty()) return
        val pool = Executors.newFixedThreadPool(WORKERS)
        try {
            val service = ExecutorCompletionService<Pair<T, R>>(pool)
            for (item in items) service.submit { if (cancelled) throw CancellationException() else item to work(item) }
            repeat(items.size) {
                check()
                val result = try {
                    service.take().get()
                } catch (e: java.util.concurrent.ExecutionException) {
                    if (cancelled) throw CancellationException()
                    throw e.cause ?: e
                }
                onResult(result.first, result.second)
            }
        } finally {
            pool.shutdownNow()
        }
    }

    private fun check() {
        if (cancelled) throw CancellationException()
    }

    private fun emit(p: ScanProgress, always: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!always && p.done != p.total && now - lastEmit < 120) return
        lastEmit = now
        onProgress(p)
    }

    private companion object {
        /** Thumbnail size analysed per photo. */
        const val SIDE = ImageMetrics.ANALYSIS_SIDE

        /** Worker threads: enough to keep decoding busy without starving the UI. */
        val WORKERS = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
    }
}
