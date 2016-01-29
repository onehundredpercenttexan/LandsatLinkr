#' Prepare image MSS and TM images for calibration/compositing  
#'
#' Prepare image MSS and TM images for calibration/compositing  
#' @param scenedir character. scene file path
#' @param demfile character. full path to scene-corresponding DEM file
#' @param process numeric. integer or vector specifying which processes to run 1=mssunpackr, 2=msswarp, 3=mssdn2rad, 4=mssatcor, 5=msscvm, 6=tmunpackr
#' @param cores numeric. number of cores to use for parallel processing
#' @import foreach
#' @import doParallel
#' @import raster
#' @export


prepare_images = function(scenedir, demfile=NULL, proj="default", process=seq(1:5), cores=2, overwrite=F){
  
  targzdir = file.path(scenedir,"targz")
  imgdir = file.path(scenedir,"images")
  
  cfun = function(a, b) NULL
  
  #mssunpackr
  if(all(is.na(match(process,1))) == F){
    print("Running mssunpackr")
    files = list.files(targzdir,"tar.gz",full.names=T)
    t=proc.time()
    if(cores == 2){
      print("...in parallel")
      cl = makeCluster(cores)
      registerDoParallel(cl)
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% mssunpackr(files[i], proj=proj, overwrite=overwrite)
      stopCluster(cl)
    } else {for(i in 1:length(files)){mssunpackr(files[i], proj=proj, overwrite=overwrite)}}
    print(proc.time()-t)
  }
  
  #geowarp
  if(all(is.na(match(process,2))) == F){
    print("Running msswarp")
    files = list.files(imgdir, pattern="archv.tif", full.names=T, recursive=T)
    diagfiles = list.files(imgdir, pattern="cloud_rmse.csv", full.names=T, recursive=T)
    tbl = do.call(rbind, lapply(diagfiles, read.table, header = F,sep = ','))
    reffile = as.character(tbl[order(round(tbl[,3],digits=1), tbl[,2]),][1,1])
    t = proc.time()
    if(cores == 2){
      print("...in parallel")
      cl=makeCluster(cores)
      registerDoParallel(cl)
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% msswarp(reffile=reffile, fixfile=files[i], sample=1000)
      stopCluster(cl)
    } else {for(i in 1:length(files)){msswarp(reffile=reffile, fixfile=files[i], sample=1000)}}
    print(proc.time()-t)
  }
  
  #convert to toa reflectance
  if(all(is.na(match(process,3))) == F){
    print("Running mssdn2refl")
    files = list.files(imgdir, pattern="archv.tif", full.names=T, recursive=T)
    t = proc.time()
    if(cores == 2){
      print("...in parallel")
      cl=makeCluster(cores)
      registerDoParallel(cl)
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% mssdn2refl(files[i], overwrite)
      stopCluster(cl)
    } else {for(i in 1:length(files)){mssdn2refl(files[i], overwrite)}}
    print(proc.time()-t)
  }
  
  #convert to surface reflectance
  if(all(is.na(match(process,4))) == F){
    print("Running msscost")
    files = list.files(imgdir, pattern="archv.tif", full.names=T, recursive=T)
    t = proc.time()
    if(cores == 2){
      print("...in parallel")
      cl=makeCluster(cores)
      registerDoParallel(cl)
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% msscost(files[i], overwrite)
      stopCluster(cl)
    } else {for(i in 1:length(files)){msscost(files[i], overwrite)}}
    print(proc.time()-t)
  }
  
  #cloudmask
  if(all(is.na(match(process,5))) == F){
    print("Running msscvm")
    files = list.files(imgdir, pattern="reflectance", full.names=T, recursive=T) #"radiance.tif"
    
    print("...Preparing DEM")
    examplefile = files[1]
    dname = dirname(examplefile)
    scenedir = substr(dname,1,nchar(dname)-12)
    topodir = file.path(scenedir,"topo")
    dir.create(topodir, showWarnings=F)
    info = get_metadata(examplefile)
    template = raster(examplefile)
    reso = xres(template)
    demname = paste(info$wrstype,"_",info$ppprrr,"_",reso,"m","_dem.tif",sep="")
    newdem = file.path(topodir,demname)
    tempdem = sub("dem.tif","temp_dem.tif",newdem)
    newslope = file.path(topodir,sub("dem","slope",demname))
    newasp = file.path(topodir,sub("dem","aspect",demname))
    newill = file.path(topodir,sub("dem","illumination",demname))
    #extname = paste(info$wrstype,"_",info$ppprrr,"_mss_image_set_union_extent.csv",sep="")
    #extfile = file.path(topodir,extname)
    s_srs = projection(template)
    t_srs = set_projection(examplefile)
    
    #havedem = file.exists(newdem)
    demfiles = list.files(topodir,"dem",full.names=T)
    #if(havedem == T & overwrite == T | havedem == F){
    unlink(demfiles)
    gdalwarp(srcfile=demfile,dstfile=tempdem,
             s_srs=s_srs,t_srs=t_srs, tr=c(60,60), dstnodata=-32768, ot="Int16")
    #}
    
    extholder = matrix(ncol = 4, nrow=length(files))
    print("...Making sure DEM is large enough")
    print("......Getting MSS image extents")
    for(i in 1:length(files)){ 
      print(i)
      img = raster(files[i])
      ext = extent(img)
      extholder[i,1] = ext@xmin
      extholder[i,2] = ext@xmax
      extholder[i,3] = ext@ymin
      extholder[i,4] = ext@ymax
    }
    adj=1500
    xmin = min(extholder[,1]) - adj
    xmax = max(extholder[,2]) + adj
    ymin = min(extholder[,3]) - adj
    ymax = max(extholder[,4]) + adj
    
    dem = raster(tempdem)
    demext = extent(dem)
    
    xminokay = demext@xmin <= xmin
    xmaxokay = demext@xmax >= xmax
    yminokay = demext@ymin <= ymin
    ymaxokay = demext@ymax >= ymax
    
    print(paste(".........DEM x minimum is okay:",xminokay))
    print(paste(".........DEM x maximum is okay:",xmaxokay))
    print(paste(".........DEM y minimum is okay:",yminokay))
    print(paste(".........DEM y maximum is okay:",ymaxokay))
    
    if(sum(c(xminokay,xmaxokay,yminokay,ymaxokay)) != 4){
      print("Error - Please make sure DEM has minimum dimensions:")
      print(paste("x minimum:", xmin))
      print(paste("x maximum:", xmax))
      print(paste("y minimum:", ymin))
      print(paste("y maximum:", ymax))
      print(paste("For projection:",t_srs))
      return("Stopping LLR")
    }
    
    #crop the dem
    print("...Croppping the DEM to MSS image set union plus 25 pixel buffer")
    gdal_translate(src_dataset=tempdem, dst_dataset=newdem, projwin=c(xmin,ymax,xmax,ymin))
    tempfiles = list.files(topodir, "temp", full.names=T)
    unlink(tempfiles)
    dem = raster(newdem)
    
    #making slope
    #haveslope = file.exists(newslope)
    slopefiles = list.files(topodir,"slope",full.names=T)
    #if(haveslope == T & overwrite == T | haveslope == F){
    unlink(slopefiles)
    print("...Preparing Slope")
    img = terrain(dem, opt="slope")
    projection(img) = set_projection(examplefile)
    img = as(img, "SpatialGridDataFrame")
    writeGDAL(img, newslope, drivername = "GTiff", type = "Float32", options="INTERLEAVE=BAND") #, mvFlag = -32768
    #}
    
    #making slope aspect
    #haveasp = file.exists(newasp)
    aspfiles = list.files(topodir,"aspect",full.names=T)
    #if(haveasp == T & overwrite == T | haveasp == F){
    unlink(aspfiles)
    print("...Preparing Aspect")
    img = terrain(dem, opt="aspect")
    projection(img) = set_projection(examplefile)
    img = as(img, "SpatialGridDataFrame")
    writeGDAL(img, newasp, drivername = "GTiff", type = "Float32", options="INTERLEAVE=BAND") #, mvFlag = -32768  
    #}
    
    img=0
    
    print("...Making masks")
    t = proc.time()
    for(i in 1:length(files)){msscvm(files[i], newdem, topoprep=T, test=F, overwrite=overwrite)} #demfile
    print(proc.time()-t)
  }
  
  #unpack tm
  if(all(is.na(match(process,6))) == F){
    print("Running tmunpackr")
    files = list.files(targzdir, pattern="tar.gz", full.names=T, recursive=T)
    reso = 30
    if(reso == 30){cores = 1}
    t = proc.time()
    if(cores == 2){
      cl=makeCluster(cores)
      registerDoParallel(cl)
      t = proc.time()
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% tmunpackr(files[i], proj=proj, overwrite=overwrite)
      stopCluster(cl)
    } else {for(i in 1:length(files)){tmunpackr(files[i], proj=proj, overwrite=overwrite)}}
    print(proc.time()-t)
  }
  
  #unpack oli
  if(all(is.na(match(process,7))) == F){
    print("Running oliunpackr")
    files = list.files(targzdir, pattern="tar.gz", full.names=T, recursive=T)
    reso = 30
    if(reso == 30){cores = 1}
    t = proc.time()
    if(cores == 2){
      cl=makeCluster(cores)
      registerDoParallel(cl)
      t = proc.time()
      o = foreach(i=1:length(files), .combine="cfun",.packages="LandsatLinkr") %dopar% oliunpackr(files[i], proj=proj, overwrite=overwrite)
      stopCluster(cl)
    } else {for(i in 1:length(files)){oliunpackr(files[i], proj=proj, overwrite=overwrite)}}
    print(proc.time()-t)
  }
}





