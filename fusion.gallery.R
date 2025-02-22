#' zchoo Tuesday, Apr 27, 2021 10:49:13 AM
#' this is to generate data tables and plots for fusions

#' @name star2grl
#' @title star2grl
#'
#' Quick utility function to convert star-fusion breakpoints to GRangesList
#'
#' @param fname (character) name of star-fusion output file
#' @param chrsub (logical) remove chr prefix default TRUE
#' @param return.type (character) Junction or GRangesList (default Junction)
#' @param mc.cores (numeric) default 16
#'
#' @param GRangesList or Junction
star2grl = function(fname, chrsub = TRUE, return.type = "Junction", mc.cores = 16) {
    dt = fread(fname)
    grl = mclapply(1:nrow(dt),
                   function(ix) {
                       left.bp.str = strsplit(dt[ix, LeftBreakpoint], ":")[[1]]
                       right.bp.str = strsplit(dt[ix, RightBreakpoint], ":")[[1]]
                       gr = GRanges(seqnames = c(gsub("chr", "", left.bp.str[1]),
                                                 gsub("chr", "", right.bp.str[1])),
                                    ranges = IRanges(start = as.numeric(c(left.bp.str[2],
                                                                          right.bp.str[2])),
                                                     width = 1),
                                    ## reverse strands to match our strand designation for junctions
                                    strand = c(ifelse(left.bp.str[3] == "+", "-", "+"),
                                               ifelse(right.bp.str[3] == "+", "-", "+"))
                                    )
                       return (gr)
                   }, mc.cores = mc.cores) %>% GRangesList
    values(grl) = dt
    if (return.type == "Junction") {
        return(Junction$new(grl = grl))
    }
    
    return(grl)
}

#' @name wgs.circos
#' @title wgs.circos
#'
#' Quick utility function for circos plot with read depth, junctions, and segments
#' (copied from skitools)
#' 
#' @param junctions Junction object with optional metadata field  $col to specify color
#' @param cov GRanges of scatter points with optional fields $col
#' @param segs GRanges of segments with optional fields $col and $border
#' @param win GRanges window to limit plot to
#' @param cytoband GRanges of cytoband
#' @param y.field field in cov that specifies the y axis to draw
#' @param cex.points cex for cov points
#' @param max.ranges max ranges for cov points (1e4)
#' @param ylim ylim on cov (default automatically computed)
#' @param cytoband.path path to UCSC style cytoband path
#' @param y.quantile quantile normalization
#' @param chr.sum whether to chr.sub everything 
#' @author Marcin Imielinski
#' @export
wgs.circos = function(junctions = jJ(),
                      cov = NULL,
                      segs = NULL,
                      win = NULL,
                      field = 'ratio',
                      cytoband = NULL,
                      y.field = field,
                      ylim = NA,
                      cytoband.path = '~/DB/UCSC/hg19.cytoband.txt',
                      cex.points = 1,
                      ideogram.outer = TRUE,
                      scatter = TRUE,
                      bar = FALSE,
                      line = FALSE,
                      gap.after = 1,
                      labels.cex = 1,
                      y.quantile = 0.9999,
                      chr.sub = TRUE,
                      max.ranges = 1e4,
                      axis.frac = 0.02,
                      palette = 'BrBg', ...)
{

    if (!file.exists(cytoband.path))
        stop('cytoband not file, must be UCSC style tsv')

    if (is.null(cytoband))
        cytoband = circlize::read.cytoband(cytoband.path)$df

    cytoband = as.data.table(cytoband)
    setnames(cytoband, c('seqnames', 'start', 'end', 'band', 'stain'))

    if (chr.sub)
        cytoband[, seqnames := gsub('chr', '', seqnames)]
    
    if (!is.null(win))
    {
        if (is.character(win) | is.integer(win) | is.numeric(win) | is.factor(win))
            win = parse.gr(as.character(win))

        if (inherits(win, 'data.frame'))
            win = dt2gr(win)

        cytoband  = as.data.table(dt2gr(cytoband) %*% win)[, .(seqnames, start, end, band, stain)]
    }

    total.width = cytoband[, sum(as.numeric(end-start))]
    if (!is.na(axis.frac) && axis.frac>0)
    {
        axis.width = ceiling(axis.frac*total.width)
        cytoband = rbind(cytoband, data.table(seqnames = 'axis', start = 0, end = axis.width, band = '', stain = ''), fill = TRUE)
    }

    if (chr.sub)
    {
        ix = ((junctions$left %>% gr.sub('chr', ''))  %^% dt2gr(cytoband)) &
            ((junctions$right %>% gr.sub('chr', '')) %^% dt2gr(cytoband))
        junctions = junctions[ix]
    }
    else
    {
        ix = junctions$left %^% dt2gr(cytoband) & junctions$right %^% dt2gr(cytoband)
        junctions = junctions[ix]
    }

    cytoband[, seqnames := as.character(seqnames)]
    args  = list(...)
    ## some important pars
    labels.cex = ifelse(is.null(args$labels.cex), 1, args$labels.cex)
    bands.height = ifelse(is.null(args$bands.height), 0.1, args$bands.height)
    cn.height = ifelse(is.null(args$cn.height), 0.3, args$cn.height)
    link.h.ratio = ifelse(is.null(args$link.h.ratio), 0.75, args$link.h.ratio)

    ## mark with colors by class
    col.dt = data.table(class = c("INV-like", "TRA-like", "DUP-like", "DEL-like"),
                        col = c(alpha("purple", 0.5),
                                alpha("green", 0.5),
                                alpha("red", 0.5),
                                alpha("blue", 0.5)))
    bpdt = junctions$dt
    bpdt[, col := col.dt$col[match(bpdt$class, col.dt$class)]]
    
    bp1 = junctions$left %>% gr2dt
    bp2 = junctions$right%>% gr2dt
    circlize::circos.clear()
    circlize::circos.par(start.degree = 90, gap.after = gap.after*1)
    circlize::circos.genomicInitialize(cytoband, sector.names = unique(cytoband$seqnames), plotType = NULL, 
                                       track.height = bands.height,
                                       labels.cex = labels.cex)

    circlize::circos.genomicTrackPlotRegion(cytoband, stack = TRUE,
                                            panel.fun = function(region, value, ...) {
                                                xlim = circlize::get.cell.meta.data("xlim")
                                                ylim = circlize::get.cell.meta.data("ylim")
                                                chr = circlize::get.cell.meta.data("sector.index") %>% gsub('chr', '', .)
                                                if (circlize::get.cell.meta.data("sector.index") != 'axis')
                                                {
                                                    circlize::circos.text(mean(xlim), 0.9, chr, cex = 1.5, facing = "clockwise", adj = c(0,1),
                                                                          niceFacing = TRUE)
                                                }
                                            }, track.height = 0.1, bg.border = NA)

    ## inner ideogram
    if (ideogram.outer)
    {
        circlize::circos.genomicTrackPlotRegion(cytoband, stack = TRUE,
                                                panel.fun = function(region, value, ...) {
                                                    xlim = circlize::get.cell.meta.data("xlim")
                                                    ylim = circlize::get.cell.meta.data("ylim")
                                                    chr = circlize::get.cell.meta.data("sector.index")
                                                    if (circlize::get.cell.meta.data("sector.index") != 'axis')
                                                    {
                                                        at = pretty(xlim, n = 3)
                                                        circlize::circos.axis(direction = "outside", labels.facing = "outside", major.at = at, minor.ticks = 10, labels = (at/1e6) %>% as.integer, labels.cex = labels.cex*0.3)
                                                        circlize::circos.genomicRect(region, value, col =  circlize::cytoband.col(value[[2]]), border = NA)
                                                        circlize::circos.rect(xlim[1], ylim[1], xlim[2], ylim[2], border = "black")
                                                    }
                                                }, track.height = 0.05, bg.border = NA)
    }
    
    ## coverage scatter plot
    if (!is.null(cov))
    {
        if (inherits(cov, 'data.frame'))
            cov = dt2gr(cov)

        cov = cov[!is.na(values(cov)[[y.field]])]
        cov = cov[!is.infinite(values(cov)[[y.field]])]

        if (is.na(ylim))
            ylim = c(0, quantile(values(cov)[[y.field]], y.quantile, na.rm = TRUE))
        
        cov$y = values(cov)[[y.field]] %>% as.numeric
        cov$y = cov$y %>% pmin(ylim[2]) %>% pmax(ylim[1])

        if (is.null(cov$col))
            cov$col = 'black'

        cov = cov[sample(length(cov), pmin(length(cov), max.ranges))]
        uchr = unique(cytoband$seqnames)
        cov = cov %&% dt2gr(cytoband)
        covdt = gr2dt(cov)[, seqnames := factor(seqnames, uchr)]
        circlize::circos.genomicTrackPlotRegion(covdt[, .(seqnames, start, end, y, as.character(col), ytop = y)],
                                                ylim = ylim,
                                                track.height = cn.height,
                                                bg.border = ifelse(uchr == 'axis', NA, alpha('black', 0.2)),
                                                panel.fun = function(region, value, ...) {
                                                    if (circlize::get.cell.meta.data("sector.index") != 'axis')
                                                    {
                                                        if (circlize::get.cell.meta.data("sector.index") == uchr[1])
                                                            circlize::circos.yaxis(side = 'left')                                    
                                                        if (scatter)
                                                            circlize::circos.genomicPoints(region, value, numeric.column = 1, col = value[[2]], pch = 16, cex = cex.points, ...)
                                                        if (bar)
                                                            circlize::circos.genomicRect(region, value[[1]], ytop.column = 1, border = value[[2]], col = value[[2]], pch = 16, cex = cex.points, ...)
                                                        if (line)
                                                            circlize::circos.genomicLines(region, value[[1]], col = value[[2]], pch = 16, cex = cex.points, ...)
                                                    }
                                                })
    }
    circlize::circos.par(cell.padding = c(0, 0, 0, 0))

    if (!is.null(segs))
    {
        if (inherits(segs, 'data.frame'))
            segs = dt2gr(segs)

        if (chr.sub)
            segs = segs %>% gr.sub('chr', '')

        segs = segs[segs %^% dt2gr(cytoband), ]

        segs = as.data.table(segs)
        if (is.null(segs$col))
            segs$col = 'gray'

        if (is.null(segs$border))
            segs$border = segs$col

        if (chr.sub)
            segs[, seqnames := gsub('chr', '', seqnames)]

        circlize::circos.genomicTrackPlotRegion(segs[, .(seqnames, start, end, col, border)], stack = TRUE,
                                                panel.fun = function(region, value, ...) {
                                                    circlize::circos.genomicRect(region, value, col = value[[1]], border = value[[2]])
                                                    xlim = circlize::get.cell.meta.data("xlim")
                                                    ylim = circlize::get.cell.meta.data("ylim")
                                                    chr = circlize::get.cell.meta.data("sector.index")
                                        #                                    circlize::circos.rect(xlim[1], ylim[1], xlim[2], ylim[2], border = "black")
                                                }, track.height = 0.05, bg.border = NA)
    }

    circlize::circos.par(cell.padding = c(0, 0, 0, 0))


    ## inner ideogram
    if (!ideogram.outer)
    {
        circlize::circos.genomicTrackPlotRegion(cytoband, stack = TRUE,
                                                panel.fun = function(region, value, ...) {
                                                    xlim = circlize::get.cell.meta.data("xlim")
                                                    ylim = circlize::get.cell.meta.data("ylim")
                                                    chr = circlize::get.cell.meta.data("sector.index")
                                                    if (circlize::get.cell.meta.data("sector.index") != 'axis')
                                                    {
                                                        at = pretty(xlim, n = 3)
                                                        circlize::circos.axis(direction = "outside", labels.facing = "outside", major.at = at, minor.ticks = 10, labels = (at/1e6) %>% as.integer, labels.cex = labels.cex*0.3)
                                                        circlize::circos.genomicRect(region, value, col = circlize::cytoband.col(value[[2]]), border = NA)
                                                        circlize::circos.rect(xlim[1], ylim[1], xlim[2], ylim[2], border = "black")
                                                    }
                                                }, track.height = 0.05, bg.border = NA)
    }

    if (nrow(bpdt))
    {

        if (is.null(bpdt$lwd))
            bpdt$lwd = NA_integer_

        bpdt[is.na(lwd), lwd := 2]

        if (is.null(bpdt$col))
            bpdt$col = NA_character_

        bpdt[is.na(col), col := 'red']

        if (is.null(bpdt$lty))
            bpdt$lty = NA_integer_

        bpdt[is.na(lty), lty := 1]

        if (nrow(bpdt))
            bpdt$span  = cut(junctions$span, c(0, 1e6, 3e8, Inf))

        spmap = structure(c(0.05, 0.2, 1), names = levels(bpdt$span))
        ixs = split(1:nrow(bpdt), bpdt$span)
        lapply(names(ixs), function(i)
            circlize::circos.genomicLink(
                bp1[ixs[[i]], .(seqnames, start, end)],
                bp2[ixs[[i]], .(seqnames, start, end)],
                h = spmap[i],
                                        #                  rou = circlize:::get_most_inside_radius()*c(0.1, 0.5, 1)[bpdt$span[ixs[[i]]] %>% as.integer],
                col = bpdt[ixs[[i]], ]$col,
                lwd =  bpdt[ixs[[i]], ]$lwd,
                lty =  bpdt[ixs[[i]], ]$lty,
                h.ratio = link.h.ratio,
                border=NA)
            )
    }

    ## create legend for junctions
    lgd_links = ComplexHeatmap::Legend(
        at = col.dt$class,
        type = "lines",
        legend_gp = gpar(col = col.dt$col, lwd = 5),
        title_position = "topleft",
        title = "Junctions",
        labels_gp = gpar(col = "black", fontsize = 15),
        title_gp = gpar(col = "black", fontsize = 25),
        grid_width = unit(10, "mm"))

    
    draw(lgd_links,
         x = unit(1, "npc") - unit(4, "mm"),
         y = unit(4, "mm"),
         just = c("right", "bottom"))

    
    circlize::circos.clear()
}

#' @name fusion.wrapper
#' @title fusion.wrapper
#'
#' @description
#'
#' Wrapper for fusions
#'
#' @param fusions.fname (character)
#' @param complex.fname (character)
#' @param cvgt.fname (character)
#' @param agt.fname (character)
#' @param gngt.fname (character)
#' @param cgc.fname (character)
#' @param ev.types (character)
#' @param pad (numeric)
#' @param height (numeric)
#' @param width (numeric)
#' @param server (character)
#' @param pair (character)
#' @param outdir (character)
#'
#' @return data.table
fusion.wrapper = function(fusions.fname = NULL,
                          complex.fname = NULL,
                          cvgt.fname = NULL,
                          gngt.fname = NULL,
                          agt.fname = NULL,
                          cgc.fname = "/data/cgc.tsv",
                          ev.types = c("qrp", "qpdup", "qrdel",
                                       "tic", "bfb", "dm", "chromoplexy",
                                       "chromothripsis", "tyfonas", "rigma", "pyrgo", "cpxdm"),
                          height = 1000,
                          width = 1000,
                          server = "",
                          pair = "",
                          pad = 1e5,
                          outdir = "./") {

    filtered.fusions = fusion.table(fusions.fname = fusions.fname,
                                    complex.fname = complex.fname,
                                    cgc.fname = cgc.fname,
                                    ev.types = ev.types)

    filtered.fusions = fusion.plot(fs = filtered.fusions,
                                   complex.fname = complex.fname,
                                   cvgt.fname = cvgt.fname,
                                   gngt.fname = gngt.fname,
                                   agt.fname = agt.fname,
                                   pad = pad,
                                   height = height,
                                   width = width,
                                   server = server,
                                   pair = pair,
                                   outdir = outdir)

    return (filtered.fusions$dt)
}

#' @name fusion.table
#' @title fusion.table
#'
#' @description
#'
#' Prepare table of fusion events for displaying
#'
#' @param fusions.fname (character) file name containing fusion gWalks
#' @param complex.fname (character) file name to events
#' @param cgc.fname (character) cancer gene census file name
#' @param ev.types (character) event types
#'
#' @return gWalk (filtered) with metadata columns:
#' - walk.id
#' - name (e.g. involved genes)
#' - num.aa (total number of aminos)
#' - gene.pc (protein coordinates)
#' - driver (logical, is a gene a driver)
#' - ev.id (complex event IDs overlapping with walk)
#' - ev.type (complex event type overlapping with walk)
fusion.table = function(fusions.fname = NULL,
                        complex.fname = NULL,
                        cgc.fname = "/data/cgc.tsv",
                        ev.types = c("qrp", "qpdup", "qrdel",
                                     "tic", "bfb", "dm", "chromoplexy",
                                     "chromothripsis", "tyfonas", "rigma", "pyrgo", "cpxdm"))
{
    if (!file.exists(fusions.fname)) {
        stop("fusions.fname does not exist")
    }
    if (!file.exists(complex.fname)) {
        stop("complex.fname does not exist")
    }
    if (!file.exists(cgc.fname)) {
        stop("cgc.fname does not exist")
    }

    ## filter to include only in-frame non-silent
    this.fusions = readRDS(fusions.fname) ## gWalk object
    if (length(this.fusions)==0) {
        return(this.fusions)
    }
    filtered.fusions = this.fusions[in.frame == TRUE & silent == FALSE & numgenes > 1]

    if (length(filtered.fusions)==0) {
        return(filtered.fusions)
    }

    ## compute total number of amino acids and mark
    grls = lapply(filtered.fusions$dt$gene.pc, parse.grl)
    n.aa = sapply(grls, function(grl) {
        wd = ifelse(!is.null(grl), sum(width(grl)), NA)
        return(wd)
    })

    filtered.fusions$set(total.aa = n.aa)

    ## filter so that gene pairs are unique (if multiple choose the one with most AA's)
    filtered.fusions = filtered.fusions[order(n.aa, decreasing = TRUE)]
    filtered.fusions = filtered.fusions[which(!duplicated(filtered.fusions$dt$genes))]

    ## return if length is 0
    if (length(filtered.fusions) == 0) {
        filtered.fusions$set(driver = c(), driver.name = c(), ev.id = c(), ev.type = c())
        return (filtered.fusions)
    }

    ## Cancer Gene Census genes
    cgc.gene.symbols = fread(cgc.fname)[Tier == 1, ][["Gene Symbol"]]

    ## annotate genes if they are in cgc
    cgc.dt = rbindlist(
        lapply(1:length(filtered.fusions),
               function(ix) {
                   ## xtYao: name seems to be integers in new gGnome??
                   ## let's use "genes" moving forward yep
                   ## gns = unlist(strsplit(filtered.fusions$dt$name[ix], ","))
                   gns = unlist(strsplit(filtered.fusions$dt$genes[ix], ","))
                   gene.in.cgc = any(gns %in% cgc.gene.symbols)
                   gns.filtered = gns[which(gns %in% cgc.gene.symbols)]
                   cgc.names = paste(gns.filtered, collapse = ", ")
                   return(data.table(driver = gene.in.cgc, driver.name = cgc.names))
               }),
        fill = TRUE)

    filtered.fusions$set(driver = cgc.dt$driver, driver.name = cgc.dt$driver.name)

    ## get chromosomes touched by each
    fs.chroms = sapply(1:length(filtered.fusions),
                       function(ix) {
                           ix.seqnames = seqnames(filtered.fusions[ix]$grl[[1]]) %>% as.character
                           ix.split.seqnames = split(ix.seqnames,
                                                     cumsum(c(1, abs(diff(as.numeric(as.factor(ix.seqnames)))))))
                           out = lapply(1:length(ix.split.seqnames),
                                        function(j) {unique(ix.split.seqnames[[j]])})
                           return(paste(out, collapse = "->"))
                       })

    filtered.fusions$set(chroms = fs.chroms)

    ## grab GRanges for each walk
    fs.grl = filtered.fusions$grl
    values(fs.grl) = filtered.fusions$dt[, .(walk.id)]
    fs.gr = stack(fs.grl)

    ## overlap with complex events
    filtered.fusions$set(ev.id = NA, ev.type = NA)
    this.ev = readRDS(complex.fname)$meta$events
    if (nrow(this.ev)) {
        this.ev = this.ev[type %in% ev.types,]
        if (nrow(this.ev)) {
            ev.grl = parse.grl(this.ev$footprint)
            values(ev.grl) = this.ev
            ev.gr = stack(ev.grl)

            ev.gr$ev.id = paste(ev.gr$type, ev.gr$ev.id, sep = "_")

            ov = gr.findoverlaps(fs.gr, ev.gr,
                                 qcol = c("walk.id"),
                                 scol = c("ev.id", "type"),
                                 return.type = "data.table")

            if (ov[,.N] > 0){
                ## ov = ov[, .(ev.id = paste(unique(ev.id), sep = ","), type = paste(unique(type), sep = ",")), by = walk.id]
                ov = ov[, .(ev.id = paste(unique(ev.id), collapse = ","), type = paste(unique(type), collapse = ",")), by = walk.id]
                pmt = match(filtered.fusions$dt$walk.id, ov$walk.id)
                filtered.fusions$set(ev.id = ov$ev.id[pmt])
                filtered.fusions$set(ev.type = ov$type[pmt])
            }
        }
    }

    return(filtered.fusions)
}

#' @name fusion.plot
#' @title fusion.plot
#'
#' @description
#'
#' Create .png files for each fusion
#'
#' @param fs (gWalk) gWalk object containing filtered fusions
#' @param complex.fname (character)
#' @param cvgt.fname (character) coverage gTrack file name
#' @param gngt.fname (character) gencode gTrack file name
#' @param agt.fname (character) allele gTrack file name
#' @param pad (numeric) gWalk pad for plotting default 1e5
#' @param height (numeric) plot height default 1e3
#' @param width (numeric) plot width default 1e3
#' @param server (character) server url
#' @param pair (character) pair id
#' @param outdir (character) output directory
#'
#' @return gWalk with additional columns plot.fname (input to slickR)
fusion.plot = function(fs = NULL,
                       complex.fname = NULL,
                       cvgt.fname = NULL,
                       agt.fname = NULL,
                       gngt.fname = "/data/gt.ge.hg19.rds",
                       pad = 1e5,
                       height = 1e3,
                       width = 1e3,
                       server = "",
                       pair = "",
                       outdir = "./") {

    if (!file.exists(cvgt.fname)) {
        stop("cvgt.fname does not exist")
    }
    if (!file.exists(gngt.fname)) {
        stop("gngt.fname does not exist")
    }
    if (!file.exists(complex.fname)) {
        stop("complex.fname does not exist")
    }

    fs = fs$copy

    ## read gTracks
    cvgt = readRDS(cvgt.fname)
    gngt = readRDS(gngt.fname)
    this.complex = readRDS(complex.fname)
    
    this.complex.gt = this.complex$gt

    ## format gTracks
    cvgt$ylab = "CN"
    cvgt$name = "cov"
    cvgt$yaxis.pretty = 3
    cvgt$xaxis.chronly = TRUE
    cvgt$y0 = 0

    this.complex.gt$ylab = "CN"
    this.complex.gt$name = "JaBbA"
    this.complex.gt$yaxis.pretty = 3
    this.complex.gt$chronly = TRUE
    this.complex.gt$y0 = 0

    gngt$xaxis.chronly = TRUE
    gngt$name = "genes"

    ## read allele gTrack if provided
    if (!is.null(agt.fname)) {
        if (file.exists(agt.fname)) {
            agt = readRDS(agt.fname)
            agt$ylab = "CN"
            agt$yaxis.pretty = 3
            agt$xaxis.chronly = TRUE
            agt$y0 = 0

        } else {
            agt = NULL
        }
    } else {
        agt = NULL
    }

    plot.dt = lapply(seq_along(fs),
                     function (ix) {
                         fn = file.path(outdir, "fusions", paste0("walk", fs$dt$walk.id[ix], ".png"))
                         fs.gt = fs[ix]$gt

                         ## formatting
                         fs.gt$name = "gWalk"
                         fs.gt$labels.suppress = TRUE
                         fs.gt$labels.suppress.grl = TRUE
                         fs.gt$xaxis.chronly = TRUE

                         if (is.null(agt)) {
                             gt = c(gngt, cvgt, this.complex.gt, fs.gt)
                         } else {
                             gt = c(gngt, agt, cvgt, this.complex.gt, fs.gt)
                         }
                         gt$xaxis.chronly = TRUE

                         ## format window
                         win = fs[ix]$footprint

                         ## grab plot link
                         plot.link = paste0(server, "index.html?file=", pair, ".json&location=",
                                            gr.string(win), "&view=")

                         if (pad > 0 & pad <= 1) {
                             adjust = pmax(1e5, pad * width(win))
                             win = GenomicRanges::trim(win + adjust)
                         } else {
                             win = GenomicRanges::trim(win + pad)
                         }

                         ppng(plot(gt,
                                   win,
                                   legend.params = list(plot = FALSE)),
                              title = paste(fs$dt$genes[ix], "|", "walk", fs$dt$walk.id[ix]),
                              filename = fn,
                              height = height,
                              width = width)

                         out.dt = data.table(
                             id = ix,
                             plot.fname = fn,
                             plot.link = plot.link)
                         
                         return(out.dt)
                     }) %>% rbindlist(use.names = TRUE)

    plot.dt = unique(plot.dt, by = "id")

    ## set plot link and file name as metadata in gWalk
    fs$set(plot.fname = plot.dt$plot.fname, plot.link = plot.dt$plot.link)
    
    return(fs)
}

