<?xml version="1.0" encoding="UTF-8"?>
<!-- This Source Code Form is subject to the terms of the Mozilla Public
     License, v. 2.0. If a copy of the MPL was not distributed with this
     file, You can obtain one at http://mozilla.org/MPL/2.0/.

     This Source Code Form is "Incompatible With Secondary Licenses", as
     defined by the Mozilla Public License, v. 2.0.
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <!-- Nicer Filenames -->
    <xsl:param name="use.id.as.filename" select="1"/>

    <!-- Label sections if they aren't automatically labeled -->
    <xsl:param name="section.autolabel" select="1"/>
    <xsl:param name="section.label.includes.component.label" select="1"/>

    <!-- Table of Contents Depth -->
    <xsl:param name="toc.section.depth">2</xsl:param>
    <xsl:param name="generate.section.toc.level" select="0"/>

    <!-- Show titles of next/previous page -->
    <xsl:param name="navig.showtitles">1</xsl:param>

    <!-- Tidy up the HTML a bit... -->
    <xsl:param name="html.cleanup" select="1"/>
    <xsl:param name="make.valid.html" select="1"/>
    <xsl:param name="html.stylesheet">../../style.css</xsl:param>
    <xsl:param name="highlight.source" select="1"/>

    <!-- Use Graphics, specify their Path and Extension -->
    <xsl:param name="admon.graphics" select="1"/>
    <xsl:param name="admon.graphics.path">../images/</xsl:param>
    <xsl:param name="admon.graphics.extension">.gif</xsl:param>
    <xsl:param name="admon.textlabel" select="0"/>
    <xsl:param name="admon.style">margin-left: 1em; margin-right: 1em</xsl:param>
</xsl:stylesheet>
