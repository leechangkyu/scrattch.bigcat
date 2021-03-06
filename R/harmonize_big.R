#' joint analysis
#' 
#' @param m A matrix or sparse matrix
#' 
#' @return a sparse matrix of Jaccard distances.
#' @export
#' library(Matrix)
#library(ggplot2)
library(matrixStats)

jet.colors <-colorRampPalette(c("#00007F", "blue", "#007FFF", "cyan","#7FFF7F", "yellow", "#FF7F00", "red", "#7F0000"))
blue.red <-colorRampPalette(c("blue", "white", "red"))



sample_cl_dat <- function(comb.dat, sets, cl, cl.sample.size=200)
  {
    dat.list = with(comb.dat, sapply(sets, function(set){
      select.cells = intersect(row.names(meta.df)[meta.df$platform==set], names(cl))
      tmp.cl = cl[select.cells]
      if(is.factor(tmp.cl)){
        tmp.cl = droplevels(tmp.cl)
      }
      select.cells = sample_cells(tmp.cl,cl.sample.size)
      get_logNormal(dat.list[[set]], select.cells, select.genes=common.genes)
    },simplify=F))
    return(dat.list)
  }


get_cells_logNormal <- function(comb.dat, cells)
  {
    dat = matrix(0, nrow=length(comb.dat$common.genes),ncol=length(cells), dimnames=list(comb.dat$common.genes, cells))
    for(set in names(comb.dat$dat.list)){
      select.cells = intersect(cells, comb.dat$dat.list[[set]]$col_id)
      if(length(select.cells)>0){
         tmp.dat = get_logNormal(comb.dat$dat.list[[set]], select.cells, select.genes=comb.dat$common.genes)
         dat[,colnames(tmp.dat)] = as.matrix(tmp.dat)
       }
    }
    return(dat)
  }


##comb.dat include the following elements
##dat.list a list of data matrix
##ref.de.param.list the DE gene criteria for each reference dataset (optional)
##meta.df merged meta data for all datasets. 
##cl.list clusters for each dataset (optional)
##cl.df.list cluster annotations for each dataset (optional) 


prepare_harmonize_big <- function(dat.list, meta.df=NULL, cl.list=NULL, cl.df.list = NULL, de.param.list=NULL, de.genes.list=NULL, rename=TRUE)
  {
    common.genes = dat.list[[1]]$row_id
    for(x in 2:length(dat.list)){
      common.genes= intersect(common.genes, dat.list[[x]]$row_id)
    }
    if(rename){
      for(x in names(dat.list)){
        dat.list[[x]]$col_id = paste(x, dat.list[[x]]$col_id, sep=".")
      }
      if(!is.null(cl.list)){
        for(x in names(cl.list)){
          names(cl.list[[x]]) = paste(x, names(cl.list[[x]]), sep=".")
        }
      }
    }
    
    platform = do.call("c",lapply(names(dat.list), function(p){
      dat = dat.list[[p]]
      setNames(rep(p, length(dat$col_id)), dat$col_id)
    }))
    #gene.counts <- do.call("c",lapply(names(dat.list), function(p){
    #  dat = dat.list[[p]]
    #  setNames(bg_colSums(dat > 0), colnames(dat))
    #}))
    df = data.frame(platform)
    if(!is.null(meta.df)){
      common.cells = intersect(row.names(meta.df), row.names(df))
      meta.df = cbind(meta.df[common.cells,,drop=F], df[common.cells,,drop=F])
    }
    else{
      meta.df = df
    }
    all.cells = unlist(lapply(dat.list, function(x)x$col_id))
    comb.dat = list(dat.list=dat.list, meta.df = meta.df, cl.list=cl.list, cl.df.list = cl.df.list, de.genes.list = de.genes.list, de.param.list= de.param.list, common.genes=common.genes, all.cells= all.cells)
  }



test_knn <- function(knn, cl, reference, ref.cl)
  {
    library(reshape)
    library(ggplot2)
    cl=  cl[row.names(knn)]
    if(is.factor(cl)){
      cl = droplevels(cl)
    }
    ref.cl =ref.cl[reference]
    if(is.factor(ref.cl)){
      ref.cl = droplevels(ref.cl)
    }
    if(length(unique(cl)) <=1 | length(unique(ref.cl)) <= 1){
      return(NULL)
    }
    pred.result = predict_knn(knn, reference, ref.cl)
    pred.prob = as.matrix(pred.result$pred.prob)
    cl.pred.prob=as.matrix(do.call("rbind",tapply(names(cl), cl, function(x){
      colMeans(pred.prob[x,,drop=F])
    })),ncol=ncol(pred.prob))
    
    tmp <- apply(cl.pred.prob, 1, which.max)
    cl.pred.prob = cl.pred.prob[order(tmp),]
    
    match.cl = setNames(tmp[as.character(cl)], names(cl))
    match_score = get_pair_matrix(pred.prob, names(match.cl), match.cl)
    
    cl.score = sum(apply(cl.pred.prob, 1, max))/sum(cl.pred.prob)
    cell.score =  mean(match_score)
    tb.df = melt(cl.pred.prob)
    tb.df[[1]] = factor(as.character(tb.df[[1]]), levels=row.names(cl.pred.prob))
    tb.df[[2]] = factor(as.character(tb.df[[2]]), levels=colnames(cl.pred.prob))
    colnames(tb.df) = c("cl","ref.cl", "freq")
    g <- ggplot(tb.df, 
                aes(x = cl, y = ref.cl)) + 
                  geom_point(aes(color = freq)) + 
                    theme(axis.text.x = element_text(vjust = 0.1,
                            hjust = 0.2, 
                            angle = 90,
                            size = 7),
                          axis.text.y = element_text(size = 6)) + 
                            scale_color_gradient(low = "white", high = "darkblue") + scale_size(range=c(0,3))
    return(list(cl.score=cl.score, cell.score= cell.score, cell.pred.prob = pred.prob, cl.pred.prob = cl.pred.prob, g=g))
  }


sample_sets_list <- function(cells.list, cl.list, cl.sample.size=100, sample.size=5000)
  {
    for(x in names(cells.list)){
      if(length(cells.list[[x]]) > sample.size){
        if(is.null(cl.list[[x]])){
          cells.list[[x]] = sample(cells.list[[x]], sample.size)
        }
        else{
          tmp.cl = cl.list[[x]][cells.list[[x]]]
          if(is.factor(tmp.cl)){
            tmp.cl = droplevels(tmp.cl)
          }
          good.cl=sum(table(tmp.cl) > 10)
          cells.list[[x]] = sample_cells(tmp.cl, max(cl.sample.size,round(sample.size/good.cl)))
        }
      }
    }
    return(cells.list)
  }


get_knn <- function(dat, ref.dat, k, method ="cor", dim=NULL)
  {
    
    print(method)
    if(method=="cor"){
      knn.index = knn_cor(ref.dat, dat,k=k)  
    }
    else if(method=="cosine"){
      knn.index = knn_cosine(ref.dat, dat,k=k)  
    }
    else if(method=="RANN"){
      knn.index = RANN::nn2(t(ref.dat), t(dat), k=k)[[1]]
    }
    else if(method == "CCA"){
      mat3 = crossprod(ref.dat, dat)
      cca.svd <- irlba(mat3, dim=dim)
      knn.index = knn_cor(cca.svd$u, cca.svd$v,  k=k)
    }
    else{
      stop(paste(method, "method unknown"))
    }
    row.names(knn.index) = colnames(dat)
    return(knn.index)
  }


select_joint_genes_big <-  function(comb.dat, ref.dat.list, select.cells = comb.dat$all.cells, maxGenes=2000, vg.padj.th=0.5, max.dim=20,use.markers=TRUE, top.n=100,rm.eigen=NULL, conservation.th = 0.5,rm.th=rep(0.7,ncol(rm.eigen)))
  {
    require(matrixStats)
    select.genes = lapply(names(ref.dat.list), function(ref.set){
      ref.dat = ref.dat.list[[ref.set]]
      ref.cells=colnames(ref.dat)
      cat(ref.set, length(ref.cells),"\n")
      tmp.cells=  intersect(select.cells, ref.cells)
##if cluster membership is available, use cluster DE genes
      if(use.markers & !is.null(comb.dat$de.genes.list[[ref.set]])){
        cl = droplevels(comb.dat$cl.list[[ref.set]][tmp.cells])
        cl.size = table(cl)
        cl = droplevels(cl[cl %in% names(cl.size)[cl.size > comb.dat$de.param.list[[ref.set]]$min.cells]])
        if(length(levels(cl)) <= 1){
          return(NULL)
        }
        de.genes = comb.dat$de.genes.list[[ref.set]]
        print(length(de.genes))     
        select.genes = display_cl(cl, norm.dat=ref.dat, max.cl.size = 200, n.markers=20, de.genes= de.genes)$markers
        select.genes = intersect(select.genes, common.genes)
      }
##if cluster membership is not available, use high variance genes and genes with top PCA loading
      else{
        tmp.dat = ref.dat
        tmp.dat@x = 2^tmp.dat@x - 1
        vg = find_vg(tmp.dat)
        rm(tmp.dat)
        gc()
        select.genes = row.names(vg)[which(vg$loess.padj < vg.padj.th | vg$dispersion >3)]
        if(length(select.genes) < 5){
          return(NULL)
        }
        select.genes = head(select.genes[order(vg[select.genes, "padj"],-vg[select.genes, "z"])],maxGenes)
        rd = rd_PCA(norm.dat=ref.dat,select.genes, ref.cells, max.pca = max.dim)
        if(is.null(rd)){
          return(NULL)
        }
        rd.dat = rd$rd.dat
        rot = t(rd$pca$rotation[,1:ncol(rd$rd.dat)])
        if(!is.null(rm.eigen)){
          rm.cor=cor(rd.dat, rm.eigen[row.names(rd.dat),])
          rm.cor[is.na(rm.cor)]=0
          select = colSums(t(abs(rm.cor)) >= rm.th) ==0
          print("Select PCA")
          print(table(select))
          if(sum(select)==0){
            return(NULL)
          }
          rot = rot[select,,drop=FALSE]
        }
        if(is.null(rot)){
          return(NULL)
        }
        rot.scaled = (rot  - rowMeans(rot))/rowSds(rot)
        gene.rank = t(apply(-abs(rot.scaled), 1, rank))
        select = gene.rank <= top.n & abs(rot.scaled ) > 2
        select.genes = colnames(select)[colSums(select)>0]
      }
    })
    gene.score = table(unlist(select.genes))
    if(length(gene.score)==0){
      return(NULL)
    }
    select.genes= names(head(sort(gene.score, decreasing=T), maxGenes))
    #gg.cons = gene_gene_cor_conservation(ref.dat.list, select.genes, select.cells)
    #select.genes = row.names(gg.cons)[gg.cons > conservation.th]
    return(select.genes)
  }


#' .. content for \description{} (no empty lines) ..
#'
#' .. content for \details{} ..
#' @title 
#' @param comb.dat 
#' @param select.sets 
#' @param select.cells 
#' @param select.genes 
#' @param method 
#' @param k 
#' @param sample.size 
#' @param cl.sample.size 
#' @param ... 
#' @export
#' @return 
#' @author Zizhen Yao
knn_joint <- function(comb.dat, ref.sets=names(comb.dat$dat.list), select.sets= names(comb.dat$dat.list), merge.sets=ref.sets, select.cells=comb.dat$all.cells, select.genes=NULL, method="cor", self.method = "RANN", k=15,  sample.size = 5000, cl.sample.size = 100, block.size = 10000, verbose=TRUE,ncores=1,...)
{
  if(length(select.cells) < block.size){
    ncores=1
  }
  #attach(comb.dat)
  with(comb.dat,{
  cat("Number of select cells", length(select.cells), "\n")
  cells.list = split(select.cells, meta.df[select.cells, "platform"])[select.sets]
  cells.list =  sample_sets_list(cells.list, cl.list[names(cl.list) %in% select.sets], sample.size=sample.size, cl.sample.size = cl.sample.size)
  ref.list = cells.list[ref.sets]
  ref.sets = ref.sets[sapply(ref.list,length) >= sapply(de.param.list[ref.sets], function(x)x$min.cells)]
  if(length(ref.sets)==0){
    return(NULL)
  }
  ref.list = ref.list[ref.sets]
##Select genes for joint analysis
  cat("Get ref.dat.list\n")
  ref.dat.list = sapply(ref.sets, function(ref.set){
    get_logNormal(dat.list[[ref.set]], ref.list[[ref.set]], select.genes=common.genes)
  },simplify=F)
  if(is.null(select.genes)){
    select.genes = select_joint_genes_big(comb.dat, ref.dat.list = ref.dat.list,select.cells=select.cells, ...)
  }
  if(length(select.genes) < 5){
    return(NULL)
  }
  cat("Number of select genes", length(select.genes), "\n")
  cat("Get knn\n")
  knn.comb = do.call("cbind",lapply(names(ref.list), function(ref.set){
    cat("Ref ", ref.set, "\n")
    if(length(ref.list[[ref.set]]) <= k) {
      #Not enough reference points to compute k
      return(NULL)
    }
    k.tmp = k
    if(length(ref.list[[ref.set]]) <= k*2) {
      k.tmp = round(k/2)
    }
    ref.dat = ref.dat.list[[ref.set]][select.genes,]
      ##index is the index of knn from all the cells
    knn =do.call("rbind", lapply(select.sets, function(set){
      cat("Set ", set, "\n")
      map.cells=  intersect(select.cells, dat.list[[set]]$col_id)
      if(length(map.cells)==0){
        return(NULL)
      }
      if(set == ref.set & self.method=="RANN"){
        rd.dat = rd_PCA_big(big.dat=dat.list[[set]],dat = ref.dat, select.cells=map.cells, max.dim = 50, th=1, ncores=ncores)$rd.dat
        if(is.null(rd.dat)){
          rd.dat = t(get_logNormal(dat.list[[set]],map.cells, select.genes=row.names(ref.dat)))
        }
        knn = RANN::nn2(rd.dat[colnames(ref.dat),,drop=F] , rd.dat[map.cells,,drop=F], k=k.tmp)[[1]]
        row.names(knn) = map.cells
      }
      else{
        knn = big_dat_apply(big.dat = dat.list[[set]], map.cells, .combine="rbind", block.size=block.size, p.FUN=function(big.dat, cols, ref.dat, ...){
          dat = get_logNormal(big.dat, cols, select.genes=row.names(ref.dat),sparse=FALSE, keep.col=FALSE)
          get_knn(dat=dat, ref.dat, ...)
        }, ref.dat=ref.dat, k=k.tmp, method=method, ncores=ncores)
        
                                        #knn=get_knn_batch(big.dat = dat.list[[set]], select.cells= map.cells, select.genes=select.genes, ref.dat = ref.dat, k=k.tmp, method = self.method, batch.size = batch.size)
      }
      if(!is.null(cl.list)){
        test.knn = test_knn(knn, cl.list[[set]], colnames(ref.dat), cl.list[[ref.set]])
        if(!is.null(test.knn)){
          cat("Knn", set, ref.set, method, "cl.score", test.knn$cl.score, "cell.score", test.knn$cell.score,"\n")
        }
      }
      idx = match(colnames(ref.dat), all.cells)
      tmp.cells = row.names(knn)
      knn = matrix(idx[knn], nrow=nrow(knn))
      row.names(knn) = tmp.cells
      knn[map.cells,,drop=F]
    }))
  }))
  #####
  #save(knn.comb, file="knn.comb.rda")
  sampled.cells = unlist(cells.list)
  #result = knn_jaccard_leiden(knn.comb[sampled.cells,])
  result = knn_jaccard_louvain(knn.comb[sampled.cells,])
  result$cl.mat = t(result$memberships)
  row.names(result$cl.mat) = sampled.cells
  result$knn = knn.comb
  result$ref.list = ref.list
  save(result, file="result.rda")
  cl = setNames(result$cl.mat[,1], row.names(result$cl.mat))
  if(length(cl) < nrow(result$knn)){
    pred.df = predict_knn(result$knn, all.cells, cl)$pred.df
    pred.cl= setNames(as.character(pred.df$pred.cl), row.names(pred.df))
    cl = c(cl, pred.cl[setdiff(names(pred.cl), names(cl))])
    #cl = pred.cl
  }
  cl.platform.counts = table(meta.df[names(cl), "platform"],cl)
  print(cl.platform.counts)
  ##If a cluster is not present in reference sets, split the cells based on imputed cluster based on cells in reference set.
  ref.de.param.list = de.param.list[ref.sets]
  cl.min.cells = sapply(ref.de.param.list, function(x)x$min.cells)
  cl.big= cl.platform.counts[ref.sets,,drop=F] >= cl.min.cells
  bad.cl = colnames(cl.big)[colSums(cl.big) ==0]
  cl.big = setdiff(colnames(cl.big), bad.cl)
  if(length(cl.big)==0){
    return(NULL)
  }
  if(length(bad.cl) > 0){
    print("Bad.cl")
    print(bad.cl)
    tmp.cells = names(cl)[cl %in% bad.cl]
    pred.prob = predict_knn(knn.comb[tmp.cells,,drop=F], comb.dat$all.cells, cl)$pred.prob
    pred.prob = pred.prob[,!colnames(pred.prob)%in% bad.cl,drop=F]
    pred.cl = colnames(pred.prob)[apply(pred.prob, 1, which.max)]
    cl[tmp.cells]= pred.cl
  }
  merge.dat.list = sapply(merge.sets, function(x){
    tmp.cells = with(comb.dat,intersect(row.names(meta.df)[meta.df$platform==x], names(cl)))
    if(length(tmp.cells)==0){
      return(NULL)
    }
    sampled.cells = sample_cells(cl[tmp.cells],200)
    get_logNormal(comb.dat$dat.list[[x]], sampled.cells, select.genes=common.genes)
  },simplify=F)

  cl= merge_cl_multiple(comb.dat=comb.dat, merge.dat.list=merge.dat.list, cl=cl, anchor.genes=select.genes)
  if(length(unique(cl))<=1){
    return(NULL)
  }
  print(table(cl))
  result$cl = cl
  result$select.genes= select.genes
  result$ref.de.param.list = ref.de.param.list
  return(result)
}
)}



sim_knn <- function(sim, k=15)
{
  
  th =  rowOrderStats(as.matrix(sim), which=ncol(sim)-k+1)
  select = sim >= th
  knn.idx = t(apply(select, 1, function(x)head(which(x),k)))
  return(knn.idx)
}

knn_cor <- function(ref.dat, query.dat, k = 15)
{
  #sim = cor(as.matrix(query.dat), as.matrix(ref.dat), use="pairwise.complete.obs")
  sim = cor(as.matrix(query.dat), as.matrix(ref.dat))
  sim[is.na(sim)] = 0
  knn.idx = sim_knn(sim, k=k)
  return(knn.idx)
}

knn_cosine <- function(ref.dat, query.dat, k = 15)
  {
    library(qlcMatrix)
    sim=cosSparse(query.dat, ref.dat)
    sim[is.na(sim)] = 0
    knn.idx = sim_knn(sim, k=k)
    return(knn.idx)
  }


jaccard2 <- function(m) {
  library(Matrix)
  
  # common values:
  A <-  tcrossprod(m)
  B <- as(A, "dgTMatrix")
  
  # counts for each row
  b <- Matrix::rowSums(m)  
  
   
  # Jacard formula: #common / (#i + #j - #common)
  x = B@x / (b[B@i+1] + b[B@j+1] - B@x)
  B@x = x
  return(B)
}


knn_jaccard <- function(knn.index)
  {
    knn.df = data.frame(i = rep(1:nrow(knn.index), ncol(knn.index)), j=as.vector(knn.index))
    knn.mat = sparseMatrix(i = knn.df[[1]], j=knn.df[[2]], x=1)
    sim= jaccard2(knn.mat)
    row.names(sim) = colnames(sim) = row.names(knn.index)
    return(sim)
  }


knn_jaccard_louvain <- function(knn.index)
  {
    require(igraph)
    cat("Get jaccard\n")
    sim=knn_jaccard(knn.index)
    cat("Louvain clustering\n")
    gr <- igraph::graph.adjacency(sim, mode = "undirected", 
                                  weighted = TRUE)
    result <- igraph::cluster_louvain(gr)
    return(result)
  }

knn_jaccard_leiden <- function(knn.index)
  {
    require(igraph)
    require(leiden)
    cat("Get jaccard\n")
    sim=knn_jaccard(knn.index)
    cat("leiden clustering\n")
    result <- leiden(sim)
    return(result)
  }


predict_knn <- function(knn.idx, reference, cl)
  {
    query = row.names(knn.idx)
    df = data.frame(nn=as.vector(knn.idx), query=rep(row.names(knn.idx), ncol(knn.idx)))
    df$nn.cl = cl[reference[df$nn]]
    tb=with(df, table(query, nn.cl))
    tb = tb/ncol(knn.idx)
    pred.cl = setNames(colnames(tb)[apply(tb, 1, which.max)], row.names(tb))
    pred.score = setNames(rowMaxs(tb), row.names(tb))
    pred.df = data.frame(pred.cl, pred.score)
    return(list(pred.df=pred.df, pred.prob = tb))
  }




impute_knn_old <- function(knn.idx, reference, dat)
  {
    query = row.names(knn.idx)
    impute.dat= sapply(1:ncol(dat), function(x){
      print(x)
      tmp.dat = sapply(1:ncol(knn.idx), function(i){
        dat[reference[knn.idx[,i]],x]
      })
      rowMeans(tmp.dat, na.rm=TRUE)
    })
    impute.dat = impute.dat / ncol(knn.idx)
    row.names(impute.dat) = row.names(knn.idx)
    colnames(impute.dat) = colnames(dat)
    return(impute.dat)
  }


impute_knn <- function(knn.idx, reference, dat)
  {
    query = row.names(knn.idx)
    impute.dat= matrix(0, nrow=nrow(knn.idx),ncol=ncol(dat))    
    k = rep(0, nrow(knn.idx))
    for(i in 1:ncol(knn.idx)){
      print(i)
      nn = reference[knn.idx[,i]]
      ##Ignore the neighbors not present in imputation reference
      select = nn %in% row.names(dat)
      impute.dat[select,]= impute.dat[select,] +  dat[nn[select],]
      k[select] = k[select]+1
    }
    impute.dat = impute.dat / k
    row.names(impute.dat) = row.names(knn.idx)
    colnames(impute.dat) = colnames(dat)
    return(impute.dat)
  }

 

harmonize_big <- function(comb.dat, prefix, overwrite=TRUE, dir="./",...)
  {
    fn = file.path(dir, paste0(prefix, ".rda"))
    print(fn)
    if(!overwrite){
      if(file.exists(fn)){
        load(fn)
        return(result)
      }

    }
    result = knn_joint(comb.dat, ...)
    save(result, file=fn)
    if(is.null(result)){
      return(NULL)
    }
    print("Cluster size")
    print(table(result$cl))
    #g = plot_cl_meta_barplot(result$cl, meta.df[names(result$cl), "platform"])
    #g = g + theme(axis.text.x = element_text(angle=45,hjust=1, vjust=1))
    #ggsave(paste0(prefix, ".platform.barplot.pdf"),g,height=5, width=12)
    #plot_confusion(result$cl, prefix,comb.dat)
    return(result)
  }
#' .. content for \description{} (no empty lines) ..
#'
#' .. content for \details{} ..
#' @title 
#' @param comb.dat 
#' @param select.cells 
#' @param prefix 
#' @param result 
#' @param ... 
#' @export
#' @return 
#' @author Zizhen Yao
i_harmonize_big<- function(comb.dat, select.cells=comb.dat$all.cells, ref.sets=names(comb.dat$dat.list), prefix="", result=NULL, overwrite=TRUE, ...)
  {
    
    #attach(comb.dat)
    if(is.null(result)){
      result = harmonize_big(comb.dat=comb.dat, select.cells=select.cells, ref.sets=ref.sets, prefix=prefix, overwrite=overwrite,...)
    }
    if(is.null(result)){
      return(NULL)
    }
    all.results= list(result)
    names(all.results) = prefix
    cl = result$cl
    for(i in as.character(sort(unique(result$cl)))){
      tmp.result = with(comb.dat, {
        tmp.prefix=paste(prefix, i,sep=".")
        print(tmp.prefix)
        select.cells= names(cl)[cl == i]
        platform.size = table(meta.df[select.cells, "platform"])
        
        print(platform.size)
        pass.th = sapply(sets, function(set)platform.size[[set]] >= de.param.list[[set]]$min.cells)
        pass.th2 = sapply(ref.sets, function(set)platform.size[[set]] >= de.param.list[[set]]$min.cells*2)
        
        if(sum(pass.th) > 1 & sum(pass.th[ref.sets]) == length(ref.sets) & sum(pass.th2) >= 1){
          tmp.result = i_harmonize_big(comb.dat, select.cells=select.cells, ref.sets=ref.sets, prefix=tmp.prefix, overwrite=overwrite, ...)
          }
        else{
          tmp.result = NULL
        }
      })
      if(!is.null(tmp.result)){
        all.results[names(tmp.result)] = tmp.result
      }           
    }
    return(all.results)
  }



merge_knn_result <- function(split.results)
  {
    ref.cells = unlist(lapply(split.results, function(x)x$ref.cells))
    ref.cells = ref.cells[!duplicated(ref.cells)]
    markers =  unique(unlist(lapply(split.results, function(x)x$markers)))
    n.cl = 0
    cl = NULL
    cl.df = NULL
    knn = NULL
    knn.merge= NULL
    for(result in split.results){
      tmp.cl = setNames(as.integer(as.character(result$cl)) + n.cl, names(result$cl))
      tmp.cl.df = result$cl.df
      row.names(tmp.cl.df) = as.integer(row.names(tmp.cl.df)) + n.cl 
      cl = c(cl, tmp.cl)
      cl.df = rbind(cl.df, tmp.cl.df)
      n.cl = max(as.integer(as.character(cl)))
      orig.index = match(result$ref.cells, ref.cells)
      tmp.knn = result$knn[names(tmp.cl),]
      tmp.knn = matrix(orig.index[tmp.knn], nrow=nrow(tmp.knn))
      knn = rbind(knn, tmp.knn)
      tmp.knn = result$knn.merge[names(tmp.cl),]
      tmp.knn = matrix(orig.index[tmp.knn], nrow=nrow(tmp.knn))
      knn.merge = rbind(knn.merge, tmp.knn)
    }
    new.result = list(cl = as.factor(cl), cl.df = cl.df, markers=markers, knn=knn, ref.cells =ref.cells, knn.merge = knn.merge)
    return(new.result)
  }







plot_markers_cl <- function(select.genes, gene.ordered=FALSE, cl.means.list = NULL, comb.dat=NULL, cl=NULL, cl.col=NULL, prefix="",...)
  {
    jet.colors <-colorRampPalette(c("#00007F", "blue", "#007FFF", "cyan","#7FFF7F", "yellow", "#FF7F00", "red", "#7F0000"))
    blue.red <-colorRampPalette(c("blue", "white", "red"))
    if(is.null(cl.means.list)){
      cl.means.list=get_cl_means_list(comb.dat, select.genes)
    }
    else{
      cl.means.list = sapply(cl.means.list, function(x)x[select.genes,],simplify=F)
    }
    if(!gene.ordered){
      gene.hc = hclust(dist(cl.means.list[[1]]), method="ward.D")
      select.genes = select.genes[gene.hc$order]
    }
    if(is.null(cl.col)){
      cl.col = jet.colors(length(unique(cl)))
    }
    cl.col = matrix(cl.col, nrow=1)
    colnames(cl.col) = levels(cl)
    pdf(paste0(prefix, ".cl.heatmap.pdf"),...)
    for(set in names(cl.means.list)){
      dat = cl.means.list[[set]][select.genes, ]
      cexCol = min(70/ncol(dat),1)
      cexRow = min(60/nrow(dat),1)
      heatmap.3(dat, Rowv=NULL, Colv=NULL, col=blue.red(100), trace="none",dendrogram="none", cexCol=cexCol, cexRow=cexRow, ColSideColors = cl.col, main=set)
    }
    dev.off()
  }


simple_dend <- function(cl.means.list)
{
  levels = unique(unlist(lapply(cl.means.list, colnames)))
  n.counts = tmp.cor=matrix(0, nrow=length(levels), ncol=length(levels))
  row.names(n.counts) = row.names(tmp.cor)=levels
  colnames(n.counts)=colnames(tmp.cor)=levels
  for(x in cl.means.list){
    tmp.cor[colnames(x),colnames(x)] = cor(x)
    n.counts[colnames(x),colnames(x)] =   n.counts[colnames(x),colnames(x)] +1
  }
  tmp.cor = tmp.cor/n.counts
  hclust(as.dist(1-tmp.cor))
}

impute_val_cor <- function(dat, impute.dat)
  {
    gene.cor = pair_cor(dat, impute.dat)
    gene.cor[is.na(gene.cor)] = 0
    return(gene.cor)
  }



get_de_result_recursive <- function(comb.dat, all.results, sets=names(comb.dat$dat.list),ref.dat.list, max.cl.size = 300, ...)
  {
    #impute.dat.list <<- list()
    for(x in names(all.results)){
      print(x)
      result = all.results[[x]]
      cl = result$cl
      cl = cl[names(cl) %in% colnames(ref.dat.list)]
      cl = cl[sample_cells(cl, 300)]      
      de.result = get_de_result(ref.dat.list, comb.dat$de.param.list, cl = cl)
      cl.means.list = get_cl_means_list(ref.dat.list, comb.dat$de.param.list, cl=cl, sets=sets)
      de.result$comb.de.genes = comb_de_result(de.result$de.genes.list, cl.means.list = cl.means.list, common.genes=comb.dat$common.genes, ...)
      all.results[[x]]$de.result = de.result
    }
    return(all.results)
  }
        


#' .. content for \description{} (no empty lines) ..
#'
#' .. content for \details{} ..
#' @title 
#' @param comb.dat 
#' @param all.results 
#' @param select.genes 
#' @param select.cells 
#' @param ref.sets 
#' @param impute.dat.list
#' @export
#' @return 
#' @author Zizhen Yao
impute_knn_recursive <- function(comb.dat, all.results, select.genes, select.cells, ref.sets=ref.sets)
  {
    #impute.dat.list <<- list()
    for(x in names(all.results)){
      print(x)
      result = all.results[[x]]
      cl = result$cl
      ref.dat.list = sapply(ref.sets, function(ref.set){
        get_logNormal(comb.dat$dat.list[[ref.set]], result$ref.list[[ref.set]], select.genes=select.genes)
      },simplify=F)      
      if(length(impute.dat.list)==0){
        impute.genes = select.genes
      }
      else{
        if(is.null(result$select.markers)){        
          de.result = get_de_result(ref.dat.list, comb.dat$de.param.list, cl = cl)
          de.genes = names(de.result$marker.counts)
          impute.genes = intersect(de.genes, select.genes)
        }
        else{
          impute.genes = intersect(result$select.markers, select.genes)
        }
        print(length(impute.genes))
      }         
      for(ref.set in ref.sets){
        if(ref.set %in% names(result$ref.list)){
          select.cols = comb.dat$all.cells[result$knn[1,]] %in% result$ref.list[[ref.set]]
          if(sum(select.cols)==0){
            next
          }
          impute.dat = impute_knn(result$knn[,select.cols], comb.dat$all.cells, as.matrix(t(ref.dat.list[[ref.set]][impute.genes,])))
          if(is.null(impute.dat.list[[ref.set]])){
            impute.dat.list[[ref.set]] <<-  impute.dat
          }
          else{
            impute.dat.list[[ref.set]][row.names(result$knn), impute.genes] <<- impute.dat
          }
          rm(impute.dat)
          gc()
        }
      }
    }
    return(impute.dat.list)
  }


## assume within data modality have been performed
##
impute_knn_global <- function(comb.dat, split.results, ref.dat.list, select.genes, select.cells, ref.sets=comb.dat$sets, sets=comb.dat$sets, rm.eigen=NULL)
  {
    org.rd.dat.list <- list()
    knn.list <- list()
    impute.dat.list <- list()
    ref.list <- list()
    ##Impute the reference dataset in the original space globally
    for(x in ref.sets)
      {
        print(x)
        tmp.cells= select.cells[comb.dat$meta.df[select.cells,"platform"]==x]
        ref.cells = intersect(colnames(ref.dat.list[[x]]), tmp.cells)
        ref.list[[x]]= ref.cells
        rd.result <- rd_PCA_big(comb.dat$dat.list[[x]], ref.dat.list[[x]][select.genes,ref.cells], select.cells=tmp.cells, max.dim=50, th=0, rm.eigen=rm.eigen, ncores=10)
        rd.dat  = rd.result$rd.dat
        print(ncol(rd.dat))
        knn.result <- RANN::nn2(data=rd.dat[ref.cells,], query=rd.dat, k=15)
        knn <- knn.result[[1]]
        row.names(knn) = row.names(rd.dat)    
        org.rd.dat.list[[x]] = rd.result
        knn.list[[x]]=knn
        knn = knn.list[[x]]
        impute.dat.list[[x]] <- impute_knn(knn, ref.cells, as.matrix(t(ref.dat.list[[x]][select.genes,ref.cells])))
      }
    ##cross-modality Imputation based on nearest neighbors in each iteraction of clustering using anchoring genes or genes shown to be differentiall expressed. 
    for(x in names(split.results)){
      print(x)
      result = split.results[[x]]
      cl = result$cl
      for(ref.set in ref.sets){
        if(ref.set %in% names(result$ref.list)){
          tmp.cells = row.names(result$knn)
          add.cells=FALSE
          query.cells = intersect(tmp.cells[comb.dat$meta.df[tmp.cells,"platform"] != ref.set], select.cells)
          if(any(!query.cells %in% row.names(impute.dat.list[[ref.set]]))){
            add.cells=TRUE
            impute.genes = select.genes
          }
          else{
            impute.genes=intersect(select.genes,c(result$select.markers, result$select.genes))
          }
          select.cols = comb.dat$meta.df[comb.dat$all.cells[result$knn[1,]],"platform"] == ref.set
          if(sum(select.cols)==0){
            next
          }
          else{
            ref.cells = intersect(comb.dat$all.cells[unique(as.vector(knn[, select.cols]))],select.cells)            
            knn = result$knn[query.cells,select.cols]
            impute.dat = impute_knn(knn, comb.dat$all.cells, impute.dat.list[[ref.set]][ref.cells,impute.genes])
          }
          if(!add.cells){
            impute.dat.list[[ref.set]][query.cells, impute.genes] <- impute.dat
          }
          else{
            impute.dat.list[[ref.set]] <- rbind(impute.dat.list[[ref.set]],impute.dat)
          }
          rm(impute.dat)
          gc()
        }
      }
    }
    return(list(knn.list =knn.list, org.rd.dat.list = org.rd.dat.list,impute.dat.list=impute.dat.list, ref.list=ref.list))
  }

#' .. content for \description{} (no empty lines) ..
#'
#' .. content for \details{} ..
#' @title 
#' @param comb.dat 
#' @param all.results 
#' @param select.genes 
#' @param select.cells 
#' @param ref.sets 
#' @export
#' @return 
#' @author Zizhen Yao
impute_knn_cross <- function(comb.dat, all.results, select.genes, select.cells, ref.sets=ref.sets)
  {
    #impute.dat.list <<- list()
    return(impute.dat.list)
  }


gene_gene_cor_conservation <- function(dat.list, select.genes, select.cells,pairs=NULL)
  {
    sets = names(dat.list)
    gene.cor.list = sapply(sets, function(set){
      print(set)
      dat = dat.list[[set]]
      gene.cor = cor(t(as.matrix(dat[select.genes,intersect(colnames(dat),select.cells)])))
      gene.cor[is.na(gene.cor)] = 0
      gene.cor
    },simplify=F)
    if(is.null(pairs)){
      n.sets = length(sets)	
      pairs = cbind(rep(sets, rep(n.sets,n.sets)), rep(sets, n.sets))
      pairs = pairs[pairs[,1]<pairs[,2],,drop=F]
    }
    gene.cor.mat= sapply(1:nrow(pairs), function(i){
      p = pairs[i,]
      print(p)
      pair_cor(gene.cor.list[[p[1]]], gene.cor.list[[p[2]]])
    })
    colnames(gene.cor.mat) = paste0(pairs[,1],":",pairs[,2])
    return(gene.cor.mat)
  }

