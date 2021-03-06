### Baron data set
### Analysis
ulimit::memory_limit(16000)

## src
source_dir(RENV) # util functions
library(SingleCellExperiment, quietly=TRUE)
# library(M3Drop, quietly=TRUE)
library(pCMF)
source(file.path(PROJDIR, "experiment", 
                 "single_cell_data", "src_experiment.R")) # code for experiments

################################################################
## run experiment or directly load result (c.f. below)

## parameters
ncomp <- 2
nrep <- 10
dataset <- "Baron2016"

presel <- TRUE #c(TRUE, FALSE) # pre-selection ?

#### data
filename <- file.path(DATADIR, "single_cell", "Baron2016", "baron-mouse.rds")
sce <- load_data(filename)

## X
X <- t(assay(sce, "counts"))
indiv_label <- colData(sce)$cell_type1
feature_label <- rep(1, ncol(X))
rm(sce)

## M3 Drop DEA
dea_result <- tryCatch(m3drop_dea(X, indiv_label),
                       error=function(e) custom_error2(e))

## pre-filtering
Xmax <- apply(X,2,max)
keep_genes <- (Xmax>0) & (apply(X,2,function(x) sum(x!=0))>=0.05*nrow(X)) # & (Xmax<=quantile(Xmax, probs=0.95))
X <- X[,keep_genes]
indiv_label <- as.factor(indiv_label)
feature_label <- as.factor(feature_label[keep_genes])
# sum(colnames(X) %in% dea_result$Gene) / length(dea_result$Gene)

#### run experiment
parameters <- expand.grid(ncomp=ncomp, rep=1:nrep, presel=presel,
                          KEEP.OUT.ATTRS=TRUE, stringsAsFactors=FALSE)

print(paste0("number of experiment = ", nrow(parameters)))
data_to_plot_U <- NULL
data_to_plot_V <- NULL
result <- NULL
sel_spcmf <- list()
res_dimred <- list()

for(rep in 1:nrow(parameters)) {
    
    print(paste0("##### replicate ", rep))
    
    tmp_res <- experiment(parameters[rep,], 
                          dataset, X, indiv_label, feature_label)
    
    if(!is.null(tmp_res)) {
        result <- rbind(result, tmp_res$result)
        data_to_plot_U <- rbind(data_to_plot_U, tmp_res$data_to_plot_U)
        data_to_plot_V <- rbind(data_to_plot_V, tmp_res$data_to_plot_V)
        sel_spcmf[[length(sel_spcmf)+1]] <- tmp_res$sel_spcmf
        res_dimred[[length(res_dimred)+1]] <- tmp_res$res_dimred
    }
}

## averaging result
library(plyr)
library(dplyr)

library(doParallel)
registerDoParallel(cores=as.integer(NCORE))

property <- c("exp_dev", "run_time", "adjRI_U", "adjRI_V", "prop0", "ngene", "ngroup")
feature <- colnames(result)[! colnames(result) %in% c(property, "rep", "replicate")]

average_result <- ddply(result, feature, 
                        function(x) data.frame(myMean(x[property], na.rm=TRUE),
                                               myVar(x[property], na.rm=TRUE)),
                        .parallel=TRUE)

## saving
DIR <- file.path(RESDIR, "experiment", "single_cell_data")
ensure_dir(DIR)
save(list=c("data_to_plot_U", "data_to_plot_V", 
            "result", "average_result", 
            "sel_spcmf", "dea_result", "res_dimred"), 
     file=file.path(DIR, "analysis_data_baron.RData"))

################################################################
if(II) {
    ## loading result
    DIR <- file.path(RESDIR, "experiment", "single_cell_data")
    tmp <- load(file=file.path(DIR, "analysis_data_baron.RData"))
    
    ## printing result
    library(ggplot2)
    DIR <- file.path(PROJDIR, "figure", "experiment", "single_cell_data")
    ensure_dir(DIR)
    
    ## result
    print(average_result)
    
    ## selection
    sum(sel_spcmf[[1]]$genes %in% dea_result$Gene) / length(sel_spcmf[[1]]$genes)
    
    ## relevant genes
    get_gene <- function(V, quant=0.95) {
        tmp <- apply(V,1,function(x) return(sqrt(sum(x^2))))
        return(rownames(V)[tmp>quantile(tmp, probs=quant)])
    }
    
    V_pcmf <- res_dimred[[1]][[2]]$Vlog
    V_pca <- res_dimred[[1]][[4]]$V
    V_zifa <- res_dimred[[1]][[5]]$V
    
    gene_pcmf <- get_gene(V_pcmf)
    sum(gene_pcmf %in% as.character(dea_result$Gene)) / length(gene_pcmf)
    
    gene_pca <- get_gene(V_pca)
    sum(gene_pca %in% as.character(dea_result$Gene)) / length(gene_pca)
    
    gene_zifa <- get_gene(V_zifa)
    sum(gene_zifa %in% as.character(dea_result$Gene)) / length(gene_zifa)
    
    ## cell plot (supp)
    method_to_plot <- c("pcmf_restim_log", "pca", "zifa", "tsne")
    data_to_plot <- subset(data_to_plot_U, replicate==1 & method %in% method_to_plot)
    
    data_to_plot$method <- factor(data_to_plot$method,
                                  levels=c("nmf", "pcmf_restim_log", "pca", "zifa", "tsne"),
                                  labels=c("NMF", "(s)pCMF", "PCA", "ZIFA", "t-SNE"))
    g1 <- ggplot(data_to_plot, 
                 aes(x=comp1, y=comp2))
    g1 <- g1 + geom_point(aes(col=cell_cluster), size=0.1)
    g1 <- g1 + facet_wrap(~method, scales="free", nrow=1)
    g1 <- g1 + xlab("") + ylab("") + ggtitle("")
    g1 <- g1 + theme_bw() #+ theme(legend.position = 'bottom')
    g1
    
    task <- paste0("supp_analysis_data_baron_visu_cells")
    ggsave(filename=file.path(DIR, paste0(task, ".eps")),
           plot=g1, width=350, height=100, dpi=1200, scale=1, units="mm")
    
    ## gene plot (supp)
    method_to_plot <- c("spcmf_log", "pcmf_log", "pca", "zifa", "tsne")
    data_to_plot <- subset(data_to_plot_V, replicate==1 & method %in% method_to_plot)
    
    data_to_plot$method <- factor(data_to_plot$method,
                                  levels=c("nmf", "spcmf_log", "pcmf_log", "pca", "zifa", "tsne"),
                                  labels=c("NMF", "sparse pCMF", "pCMF", "PCA", "ZIFA", "t-SNE"))
    g1 <- ggplot(data_to_plot, 
                 aes(x=comp1, y=comp2))
    g1 <- g1 + geom_point(aes(col=gene_cluster), size=0.1)
    g1 <- g1 + facet_wrap(~method, scales="free", nrow=1)
    g1 <- g1 + xlab("") + ylab("") + ggtitle("")
    g1 <- g1 + theme_bw() + theme(legend.position = 'none')
    g1
    
    task <- paste0("supp_analysis_data_baron_visu_genes")
    ggsave(filename=file.path(DIR, paste0(task, ".eps")),
           plot=g1, width=290, height=80, dpi=1200, scale=1, units="mm")
}
