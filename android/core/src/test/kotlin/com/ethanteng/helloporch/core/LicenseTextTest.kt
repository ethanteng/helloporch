package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals

class LicenseTextTest {
    // The same text as iOS's testLicenseTextRewrapsToTheScreenButKeepsShortLinesAndParagraphs.
    @Test fun licenseTextRewrapsToTheScreenButKeepsShortLinesAndParagraphs() {
        val mit = "The MIT License (MIT)\n\n" +
            "Copyright (c) 2018 Roy Marmelstein\nCopyright (c) 2026 Bruno Guidolim and contributors\n\n" +
            "Permission is hereby granted, free of charge, to any person obtaining a copy\n" +
            "of this software and associated documentation files (the \"Software\"), to deal\n" +
            "in the Software.\r\n   \r\n" +
            "      \"License\" shall mean the terms and conditions for use, reproduction,\n      and distribution."
        assertEquals("The MIT License (MIT)\n\n" +
            "Copyright (c) 2018 Roy Marmelstein\nCopyright (c) 2026 Bruno Guidolim and contributors\n\n" +
            "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated " +
            "documentation files (the \"Software\"), to deal in the Software.\n\n" +
            "\"License\" shall mean the terms and conditions for use, reproduction, and distribution.", LicenseText.reflowed(mit))
    }

    @Test fun textAlreadyInParagraphsStaysAsItIs() {
        val apache = "Apache License\nVersion 2.0, January 2004\n\n1. Definitions.\n\n\"License\" shall mean the terms and conditions."
        assertEquals(apache, LicenseText.reflowed(apache))
    }
}
