package com.itsash.tidy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile

class ContentHashTest {
    private fun temp(bytes: ByteArray): File = File.createTempFile("tidy", ".bin").apply {
        deleteOnExit()
        writeBytes(bytes)
    }

    private fun partial(f: File) = RandomAccessFile(f, "r").use { ContentHash.partial(it.channel, f.length()) }

    private fun full(f: File) = RandomAccessFile(f, "r").use { ContentHash.full(it.channel) }

    @Test fun identicalFilesHaveEqualHashes() {
        val data = ByteArray(300_000) { (it * 31).toByte() }
        assertEquals(partial(temp(data)), partial(temp(data.copyOf())))
        assertEquals(full(temp(data)), full(temp(data.copyOf())))
    }

    @Test fun middleChangeFoolsPartialButNotFull() {
        val a = ByteArray(300_000) { (it * 31).toByte() }
        val b = a.copyOf().also { it[150_000] = (it[150_000] + 1).toByte() }
        assertEquals(partial(temp(a)), partial(temp(b)))
        assertNotEquals(full(temp(a)), full(temp(b)))
    }

    @Test fun smallFilesAreHashedWhole() {
        assertNotEquals(partial(temp(byteArrayOf(1, 2, 3))), partial(temp(byteArrayOf(1, 2, 4))))
    }
}
