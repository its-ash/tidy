package com.itsash.tidy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageMetricsTest {
    private val w = 64
    private val h = 64

    private fun image(f: (x: Int, y: Int) -> Int) = IntArray(w * h) { f(it % w, it / w).coerceIn(0, 255) }

    private fun hamming(a: Long, b: Long) = java.lang.Long.bitCount(a xor b)

    @Test fun flatImageHasZeroBlurScore() {
        assertEquals(0.0, ImageMetrics.blurScore(image { _, _ -> 120 }, w, h), 1e-9)
    }

    @Test fun checkerboardIsMuchSharperThanSmoothGradient() {
        val sharp = ImageMetrics.blurScore(image { x, y -> if ((x + y) % 2 == 0) 0 else 255 }, w, h)
        val smooth = ImageMetrics.blurScore(image { x, _ -> x * 4 }, w, h)
        assertTrue("sharp=$sharp smooth=$smooth", sharp > 1000 && smooth < 1 && sharp > smooth * 100)
    }

    @Test fun blurringLowersTheScore() {
        val sharp = image { x, y -> if ((x / 4 + y / 4) % 2 == 0) 30 else 220 }
        val blurred = IntArray(w * h) { i ->
            val x = i % w
            val y = i / w
            var s = 0
            var n = 0
            for (dy in -3..3) for (dx in -3..3) {
                val xx = x + dx
                val yy = y + dy
                if (xx in 0 until w && yy in 0 until h) { s += sharp[yy * w + xx]; n++ }
            }
            s / n
        }
        assertTrue(ImageMetrics.blurScore(blurred, w, h) < ImageMetrics.blurScore(sharp, w, h) / 4)
    }

    @Test fun dHashOfGradientsIsAllZerosOrAllOnes() {
        assertEquals(0L, ImageMetrics.dHash(image { x, _ -> x * 4 }, w, h))
        assertEquals(-1L, ImageMetrics.dHash(image { x, _ -> 255 - x * 4 }, w, h))
    }

    @Test fun dHashIgnoresBrightnessShift() {
        val base = image { x, y -> (x * 7 + y * 3) % 200 }
        val brighter = image { x, y -> (x * 7 + y * 3) % 200 + 40 }
        assertEquals(ImageMetrics.dHash(base, w, h), ImageMetrics.dHash(brighter, w, h))
    }

    @Test fun differentImagesAreFarApart() {
        val a = ImageMetrics.dHash(image { x, y -> if (x < 32) 200 else 20 + y }, w, h)
        val b = ImageMetrics.dHash(image { x, y -> if (y < 32) 200 else 20 + x }, w, h)
        assertNotEquals(a, b)
        assertTrue(hamming(a, b) > 6)
    }

    @Test fun fitKeepsAspectAndNeverUpscales() {
        assertEquals(256 to 128, ImageMetrics.fit(4000, 2000))
        assertEquals(100 to 50, ImageMetrics.fit(100, 50))
    }
}
