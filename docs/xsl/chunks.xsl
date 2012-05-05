<?xml version="1.0" encoding="UTF-8"?>
<!-- This Source Code Form is subject to the terms of the Mozilla Public
     License, v. 2.0. If a copy of the MPL was not distributed with this
     file, You can obtain one at http://mozilla.org/MPL/2.0/.

     This Source Code Form is "Incompatible With Secondary Licenses", as
     defined by the Mozilla Public License, v. 2.0.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <!-- Include default bugzilla XSL -->
    <xsl:include href="bugzilla-docs.xsl"/>
    <!-- Set Chunk Specific XSL Params -->
    <xsl:param name="chunker.output.doctype-public">-//W3C//DTD HTML 4.01 Transitional//EN</xsl:param>
    <xsl:param name="chunker.output.doctype-system">http://www.w3.org/TR/html4/loose.dtd</xsl:param>
    <xsl:param name="chunk.section.depth" select="1"/>
    <xsl:param name="chunk.first.sections" select="1"/>
    <xsl:param name="chunker.output.encoding" select="UTF-8"/>
    <xsl:param name="chunk.quietly" select="1"/>
</xsl:stylesheet>
