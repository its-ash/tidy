package com.itsash.tidy

import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.security.MessageDigest

/** Content hashes used to find exact duplicates. Pure JVM, unit-tested. */
object ContentHash {
    /** Bytes read from each end of a file for the cheap [partial] hash. */
    const val EDGE = 64 * 1024

    private const val BUFFER = 256 * 1024

    /** SHA-1 of the size, the first and the last [EDGE] bytes. Cheap pre-filter for [full]. */
    fun partial(ch: FileChannel, size: Long): String {
        val md = MessageDigest.getInstance("SHA-1")
        md.update(size.toString().toByteArray())
        val buf = ByteBuffer.allocate(EDGE)
        readAt(ch, 0, minOf(size, EDGE.toLong()).toInt(), buf, md)
        if (size > EDGE) {
            val tail = minOf(size - EDGE, EDGE.toLong()).toInt()
            readAt(ch, size - tail, tail, buf, md)
        }
        return hex(md.digest())
    }

    /** SHA-256 of the whole file. Returns null when [cancelled] turns true. */
    fun full(ch: FileChannel, cancelled: () -> Boolean = { false }): String? {
        val md = MessageDigest.getInstance("SHA-256")
        val buf = ByteBuffer.allocate(BUFFER)
        var pos = 0L
        while (true) {
            if (cancelled()) return null
            buf.clear()
            val n = ch.read(buf, pos)
            if (n <= 0) break
            md.update(buf.array(), 0, n)
            pos += n
        }
        return hex(md.digest())
    }

    private fun readAt(ch: FileChannel, from: Long, length: Int, buf: ByteBuffer, md: MessageDigest) {
        var done = 0
        while (done < length) {
            buf.clear()
            buf.limit(length - done)
            val n = ch.read(buf, from + done)
            if (n <= 0) break
            md.update(buf.array(), 0, n)
            done += n
        }
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
