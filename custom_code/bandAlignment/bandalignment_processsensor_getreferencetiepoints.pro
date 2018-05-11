;h+
; (c) 2018 Harris Geospatial Solutions, Inc.
; 
; Licensed under MIT, see LICENSE.txt for more details.
;h-

;+
; :Description:
;    Simple procedure that will generate tie points base don the input group.
;
; :Params:
;    group: in, requried, type=string[*]
;      Array of strigns that represents the files to process.
;    parameters: in, required, type=dictionary
;      The dictionary parameters used for all the band alignment processing.
;
; :Keywords:
;    RASTER: in, optional, type=ENVIRASTER
;      If set, then we wont stack the images into a raster. Can save a small amount of time.
;    NO_OUTPUT: in, optional, type=boolean, default=false
;      If set, then no output files will be created. Otherwise a .dat file and tie points 
;      will be saved to disk. Used for secondary image registration.
;    FILTERED_TIEPOINTS: out, optional, type=bandAlignmentTiePoints
;      Returns a direct reference to the tie points that are generated by this procedure.
;
; :Author: Zachary Norman - GitHub: znorman-harris
;-
pro BandAlignment_ProcessSensor_GetReferenceTiePoints, group, parameters, $
  RASTER = raster, $
  NO_OUTPUT = no_output, $
  FILTERED_TIEPOINTS = filtered_tiepoints
  compile_opt idl2, hidden
  e = envi(/CURRENT)
  
  ;initialize progress
  prog = awesomeENVIProgress('Generating Reference Tie points', /PRINT)
  prog.setProgress, 'Initializing', 0, /PRINT
  
  ;generate the reference tiepoints
  if ~isa(raster, 'ENVIRASTER') then begin
    raster = bandAlignment_group_to_virtualRaster(group)
  endif

  ;set task parameters - from banadalignment_set_task_parameters which ALWAYS gets called
  ;first so we should have the function defined

  ;set custom task params based on sensor
  case (parameters.SENSOR) of
    'rededge':bandalignment_set_rededge_task_parameters, parameters.CORRELATION_TASK, parameters, group
    else:;do nothing
  endcase

  ;generate reference tiepoints
  BandAlignment_GenerateReferenceTiepoints,$
    INPUT_RASTER = raster,$
    PROGRESS = prog,$
    TIEPOINT_GENERATION_TASK = ~(parameters.RIGOROUS_ALIGNMENT) ? parameters.CORRELATION_TASK : parameters.MUTUAL_TASK,$
    TIEPOINT_FILTERING_TASK = parameters.FILTER_TASK,$
    REFERENCE_BAND = parameters.BASE_BAND,$
    MINIMUM_FILTERED_TIEPOINTS = parameters.MINIMUM_FILTERED_TIEPOINTS,$
    OUTPUT_BANDALIGNMENTTIEPOINTS = filtered_tiepoints
    
  ;create output if not told to skip
  if ~keyword_set(no_output) then begin
    prog.setProgress, 'Generating output', 99, /PRINT
    
    ;save the tie points
    BandAlignment_SaveReferenceTiepoints,$
      INPUT_BANDALIGNMENTTIEPOINTS = filtered_tiepoints,$
      OUTPUT_TIEPOINTS_SAVEFILE_URI = parameters.POINTS_FILE

    ;create image that we can look at
    BandAlignment_ApplyReferenceTiePointsWithIDL,$
      INPUT_RASTER = raster,$
      INPUT_BANDALIGNMENTTIEPOINTS = filtered_tiepoints,$
      OUTPUT_DATA_POINTER = datPtr,$
      OUTPUT_SPATIALREF = outSref

    ;save to disk
    if ~file_test(parameters.RIGOROUS_DIR + '_out') then file_mkdir, parameters.RIGOROUS_DIR + '_out'
    uri = parameters.RIGOROUS_DIR + '_out' + path_sep() + file_basename(group[0], '.tif') + '.dat'
    if file_test(uri) then file_delete, uri, /QUIET
    if ~file_test(uri) then begin
      if parameters.hasKey('METADATA') then begin
        newRaster = ENVIRaster(*datPtr, SPATIALREF = outSref, URI = uri, METADATA = parameters.METADATA)
      endif else begin
        newRaster = ENVIRaster(*datPtr, SPATIALREF = outSref, URI = uri)
      endelse
      newRaster.save
      newRaster.close
    endif else begin
      print, 'Unable to create preview with alignment using reference tiepoints, file locked. File:'
      print, '  ' + uri
    endelse

    ;clean up so we dont have locks on any files
    raster.close
    foreach file, group do begin
      raster = e.openRaster(file)
      raster.close
    endforeach
  endif
  
  ;finish our progress
  prog.finish
end