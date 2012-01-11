<?xml version="1.0" encoding="UTF-8"?>
<!-- This Source Code Form is subject to the terms of the Mozilla Public
     License, v. 2.0. If a copy of the MPL was not distributed with this
     file, You can obtain one at http://mozilla.org/MPL/2.0/.

     This Source Code Form is "Incompatible With Secondary Licenses", as
     defined by the Mozilla Public License, v. 2.0.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:fo="http://www.w3.org/1999/XSL/Format"
                version="1.0">
    <!-- Some layout parameters -->
    <xsl:param name="generate.index" select="0"/>
    <xsl:param name="doc.collab.show" select="0"/>
    <xsl:param name="latex.output.revhistory" select="0"/>
    <xsl:param name="doc.lot.show"></xsl:param>
    <xsl:param name="latex.encoding">utf8</xsl:param>
    <xsl:param name="imagedata.default.scale">pagebound</xsl:param>
    <xsl:param name="latex.hyperparam">colorlinks,linkcolor=blue,urlcolor=blue</xsl:param>

    <!-- Show <ulink>s as footnotes -->
    <xsl:param name="ulink.footnotes" select="1"/>
    <xsl:param name="ulink.show" select="1"/>

    <!-- Don't use Graphics -->
    <xsl:param name="admon.graphics" select="0"/>
    <xsl:param name="callout.graphics" select="0"/>

    <!-- Make pdflatex shut up about <prompt> and <command> within <programlisting>, -->
    <!-- see http://dblatex.sourceforge.net/doc/manual/sec-verbatim.html             -->
    <xsl:template match="prompt|command" mode="latex.programlisting">
        <xsl:param name="co-tagin" select="'&lt;:'"/>
        <xsl:param name="rnode" select="/"/>
        <xsl:param name="probe" select="0"/>

        <xsl:call-template name="verbatim.boldseq">
            <xsl:with-param name="co-tagin" select="$co-tagin"/>
            <xsl:with-param name="rnode" select="$rnode"/>
            <xsl:with-param name="probe" select="$probe"/>
        </xsl:call-template>
    </xsl:template>
</xsl:stylesheet>
