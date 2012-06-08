function results = BerkeleyAverage( se, sites, options )
% results = BerkeleyAverage( stationElements, stationSites, options )
% 
% BerkeleyAverage is the main entrance function for the Berkeley Earth
% Surface Temperature Averaging Scheme.
%
% This function takes three parameters, the first is an array of
% stationElements, the second is an array of stationSites, and the third is
% an option specifier (as either a keyword or a structure generated by
% BerkeleyAverageOptions).
%
% The stationElements and stationSites are generally the output of
% loadTemperatureData or loaded from a previously saved archive.
%
% It is assumed that the station data has monthly time resolution and that
% seasonality has already been removed.
%
% Please refer to BerkeleyAverageOptions for information on supported 
% configurations and options.
%
% The output of this function is a results structure that contains the
% result of the calculation distributed across several fields.

temperatureGlobals;
session = sessionStart;

start_time = now();

frc = sessionFunctionCache;

calling_records = length(se);

types = {'monthly', 'annual', 'five_year', 'ten_year', 'twenty_year' };

% Determine which option set to use
if nargin < 3
    sessionWriteLog( 'No options specified.  Using "weighted" method by default.' );
    options = 'weighted';
    options = BerkeleyAverageOptions( options );    
else
    if ischar( options ) 
        sessionWriteLog( ['Options command: "' options '"'] );
        options = BerkeleyAverageOptions( options );    
    elseif isstruct( options ) 
        sessionWriteLog( 'Launched with custom options' );
    end
end       

sessionSectionBegin( 'Berkeley Average' );
sessionWriteLog( ['Called with ' num2str( length(se) ) ' temperature time series from ' ...
    num2str( length( unique( md5hash( sites ) ) ) ) ' unique sites'] );

% Display configuration options to screen and log
sessionWriteLog( ' ' ); 
sessionWriteLog( '-- Options Requested --' ); 
f = fieldnames( options );
for k = 1:length(f)
    if islogical(options.(f{k}))
        if options.(f{k})
            sessionWriteLog( [f{k} ': true'] );
        else
            sessionWriteLog( [f{k} ': false'] );
        end
    else
        if length(options.(f{k})) < 10
            sessionWriteLog( [f{k} ': ' num2str( options.(f{k}) )] );
        else
            sessionWriteLog( [f{k} ': vector specified'] );
        end
    end
end     

% Precompute any missing hashes    
parfor k = 1:length(se)
    se(k) = compress(se(k));
end

% Attempt to load from cache.  If the same records and the same options
% were run previously on the same code, the result is loaded from disk and
% we exit immediately.
hash = collapse( [collapse( md5hash(se) ), collapse( md5hash( sites ) ), md5hash(options)] );
result = get( frc, hash );
if ~isempty( result )
    results = result;
    sessionWriteLog( 'Loaded From Cache' );
    sessionSectionEnd( 'Berkeley Average' );
    return;
end
    
% The following code executes the "scalpel" method of breaking records into
% multiple pieces at metadata indicators and empirical breaks.
if options.UseScalpel

    sessionSectionBegin( 'Berkeley Average Scalpel Methods' );    
    
    % Metadata section
    if options.ScalpelMetadata        
        % Gaps in station records
        if options.ScalpelGaps
            [se, sites, back_map1, start_pos1] = splitStationBreaks( se, sites, ...
                options.ScalpelGapLength, options.BadFlags );
        else
            back_map1 = (1:length(se))';
            start_pos1 = ones(length(se), 1);
        end
        
        % Declared and suspected station moves
        [se, sites, back_map2, start_pos2] = splitStationMoves( se, sites, options.ScalpelDeclaredMoves, ...
            options.ScalpelSuspectedMoves );
        
        % Declared changes in time of observation
        if options.ScalpelTOBChanges
            [se, sites, back_map3, start_pos3] = splitStationTOBChange( se, sites, ...
                options.ScalpelTOBPersistence, options.BadFlags, options.ScalpelTOBDifference );
        else
            back_map3 = (1:length(se))';
            start_pos3 = ones(length(se), 1);
        end
    else
        back_map1 = (1:length(se))';
        start_pos1 = ones(length(se), 1);
        back_map2 = (1:length(se))';
        start_pos2 = ones(length(se), 1);
        back_map3 = (1:length(se))';
        start_pos3 = ones(length(se), 1);
    end
    
    % Empirical section
    if options.ScalpelEmpirical
        % Empirically determined changes in station baseline
        [se, sites, back_map4, start_pos4] = empiricalCuts( se, sites, options );
    else
        back_map4 = (1:length(se))';
        start_pos4 = ones(length(se), 1);
    end
    
    sessionSectionEnd( 'Berkeley Average Scalpel Methods' ); 
             
    % Build Reverse Split Lookup Table;
    back_map = back_map4;
    start_pos = start_pos4;
    break_flags = start_pos4.*0;
    break_flags(start_pos4 ~= 1) = 4;
    
    start_pos = start_pos + start_pos3( back_map ) - 1;
    break_flags( start_pos3( back_map ) ~= 1 & ~break_flags ) = 3;
    back_map = back_map3( back_map );
    
    start_pos = start_pos + start_pos2( back_map ) - 1;
    break_flags( start_pos2( back_map ) ~= 1 & ~break_flags ) = 2;
    back_map = back_map2( back_map );

    start_pos = start_pos + start_pos1( back_map ) - 1;
    break_flags( start_pos1( back_map ) ~= 1 & ~break_flags ) = 1;
    back_map = back_map1( back_map );
else
    start_pos = ones( length(se), 1 );
    break_flags = zeros( length(se), 1 );
    back_map = 1:length(se);
end


% This is where the real heavy lifting is actually done
results = BerkeleyAverageCore( se, sites, options );
results.options = options;  % Append options list 

% Add some additional meta data
results.execution_started = datestr(start_time);
[file_hash, dep_hash] = sessionFileHash( which(mfilename) );
results.file_hash = [file_hash, dep_hash];

results.initial_time_series = calling_records;
results.post_scalpel_time_series = length(se);

% Reconstruct the baselines and shift statistics
un = unique( back_map );
baselines(1:max(un)) = struct;

emp_shifts = zeros( length(se), 1 ).*NaN;
move_shifts = emp_shifts;
tob_shifts = emp_shifts;
gap_shifts = emp_shifts;

new_record_weights = zeros( max(un), 1 );

% Group baseline information by original site.
for k = 1:length(un)
    f = find(back_map == un(k));

    baselines(un(k)).break_positions = start_pos(f)';
    baselines(un(k)).break_flags = break_flags(f)';
    baselines(un(k)).baseline = results.baselines(f); 
    if options.FullBaselineMapping
        baselines(un(k)).geographic_anomaly = results.geographic_anomaly(f); 
        baselines(un(k)).local_anomaly = results.local_anomaly(f); 
    end
    baselines(un(k)).record_weight = results.record_weights(f)';
    baselines(un(k)).site_weight = results.site_weights(f)';
    new_record_weights(un(k)) = sum( baselines(un(k)).record_weight( ...
        ~isnan( baselines(un(k)).record_weight ) ) );
    
    for m = 1:4
        f2 = find(baselines(un(k)).break_flags == m);
        b_end = baselines(un(k)).baseline(f2);
        b_start = b_end.*NaN;
        
        offset = 1;        
        fx = (isnan(b_start) & f2 - offset > 0);
        while any(fx)
            b_start(fx) = baselines(un(k)).baseline( f2(fx) - offset );
            offset = offset + 1;
            fx = (isnan(b_start) & f2 - offset > 0);
        end
        
        % Store some summary data on the effect of scalpel
        switch m
            case 1
                gap_shifts(f(f2)) = b_end - b_start;
            case 2
                move_shifts(f(f2)) = b_end - b_start;
            case 3
                tob_shifts(f(f2)) = b_end - b_start;
            case 4
                emp_shifts(f(f2)) = b_end - b_start;
        end
    end                
end

% Update results structure with structured baseline result
results.baselines = baselines;
results.record_weights = new_record_weights;
results = rmfield( results, 'site_weights' );
if options.FullBaselineMapping
    results = rmfield( results, 'geographic_anomaly' );
    results = rmfield( results, 'local_anomaly' );
end

% Append shift statistics
if options.UseScalpel    
    % Metadata section
    if options.ScalpelMetadata        
        % Gaps in station records
        if options.ScalpelGaps
            results.gap_baseline_shifts = gap_shifts( ~isnan(gap_shifts) );
        end
        
        % Declared and suspected station moves
        % Declared changes in time of observation
        if options.ScalpelSuspectedMoves || options.ScalpelDeclaredMoves
            results.move_baseline_shifts = move_shifts( ~isnan(move_shifts) );
        end
        
        % Declared changes in time of observation
        if options.ScalpelTOBChanges
            results.tob_baseline_shifts = tob_shifts( ~isnan(tob_shifts) );
        end
    end
    
    % Empirical section
    if options.ScalpelEmpirical
        results.empirical_baseline_shifts = emp_shifts( ~isnan(emp_shifts) );
    end
    
end


% If requested, perform uncertainty calculation.
if options.ComputeUncertainty
    
    sessionSectionBegin( 'Berkeley Average Compute Uncertainty' );    
    
    % This section computes spatial uncertainty, that is the uncertainty
    % that results from incomplete spatial sampling of the globe.  It is
    % only available if the local mode mapping functions are enabled.
    if options.ComputeEmpiricalSpatialUncertainty
        % Empirical mode spatial uncertainty (preferred).
        if options.UseLandMask
            if options.GridSize == 16000
                cache = load('mask16000');
                areal_weight = cache.mask;
            else                    
                areal_weight = makeLandMask( [results.map_pts(:).lat], [results.map_pts(:).long] )';
            end
        else
            areal_weight = ones( 1, length(results.map_pts) );
        end
        results.spatial_uncertainty = computeSpatialUncertainty( results.times_monthly, ...
            results.map_pts, results.map, results.coverage_map, areal_weight, options );
        
        for m = 1:length(types)            
            t1 = results.( ['times_' types{m}] );
            t2 = results.spatial_uncertainty.( ['times_' types{m}] );
            [~, I1, I2] = intersect( t2, t1 );
            
            val = t1.*NaN;
            val(I2) = results.spatial_uncertainty.( ['unc_' types{m}] )(I1);
            
            results.spatial_uncertainty.( ['unc_' types{m}] ) = val;
            results.spatial_uncertainty = rmfield( results.spatial_uncertainty, ['times_' types{m}] );
        end
        
        % Store analytic spatial estimate alongside empirical
        if options.SupplementEmpiricalSpatialWithAnalytic
            for m = 1:length(types)            
                t1 = results.( ['times_' types{m}] );
                t2 = results.spatial_uncertainty.( ['alternative_times_' types{m}] );
                [~, I1, I2] = intersect( t2, t1 );

                val = t1.*NaN;
                val(I2) = results.spatial_uncertainty.( ['alternative_unc_' types{m}] )(I1);

                results.spatial_uncertainty.( ['alternative_unc_' types{m}] ) = val;
                results.spatial_uncertainty = rmfield( results.spatial_uncertainty, ['alternative_times_' types{m}] );
            end          
        end
    elseif options.ComputeAnalyticSpatialUncertainty
        % Alternative analytic uncertainty with no empirical
        if options.UseLandMask
            if options.GridSize == 16000
                cache = load('mask16000');
                areal_weight = cache.mask;
            else
                areal_weight = makeLandMask( [results.map_pts(:).lat], [results.map_pts(:).long] )';
            end
        else
            areal_weight = ones( length(results.map_pts), 1 );
        end
        results.spatial_uncertainty = ...
            computeAlternativeSpatialUncertainty( results.times_monthly, ...
            results.map_pts, results.coverage_map, areal_weight, results.map, options );
        for m = 1:length(types)
            t1 = results.( ['times_' types{m}] );
            t2 = results.spatial_uncertainty.( ['alternative_times_' types{m}] );
            [~, I1, I2] = intersect( t2, t1 );
            
            val = t1.*NaN;
            val(I2) = results.spatial_uncertainty.( ['alternative_unc_' types{m}] )(I1);
            
            results.spatial_uncertainty.( ['alternative_unc_' types{m}] ) = val;
            results.spatial_uncertainty = rmfield( results.spatial_uncertainty, ['alternative_times_' types{m}] );
        end
    end
    
    % This sections computes the statistical uncertainty, that is the
    % uncertainty resulting from noise and likely bias in the available
    % temperature records for the parts of the world that were sampled.
    if options.ComputeStatisticalUncertainty
        if options.LocalMode && ~options.StatisticalUncertaintyLocal
            % Used for a much faster, but highly approximate uncertainty
            
            options.LocalMode = options.StatisticalUncertaintyLocal;
            options.SiteWeightingGlobalCutoffMultiplier = options.SiteWeightingCutoffMultiplier;
            options.OutlierWeightingGlobalCutoffMultiplier = options.OutlierWeightingCutoffMultiplier;
        end
            
        % The real effort for statistical uncertainty
        results.statistical_uncertainty = computeStatisticalUncertainty( se, sites, options, results );

        for m = 1:length(types)            
            t1 = results.( ['times_' types{m}] );
            t2 = results.statistical_uncertainty.( ['times_' types{m}] );
            [~, I1, I2] = intersect( t2, t1 );
            
            val = t1.*NaN;
            val(I2) = results.statistical_uncertainty.( ['unc_' types{m}] )(I1);
            
            results.statistical_uncertainty.( ['unc_' types{m}] ) = val;
            results.statistical_uncertainty = rmfield( results.statistical_uncertainty, ['times_' types{m}] );
        end    
        
        % Prepare the statistical uncertainty samples to use the same
        % timescale as the total result
        groups = results.statistical_uncertainty.groups;
        sz = size( groups );
        new_groups = cell(sz(1),1);
        for m = 1:sz(1)
            sz2 = size( groups{m,2} );
            vals = zeros( length(results.times_monthly), sz2(2) ).*NaN;
            
            [~,I1,I2] = intersect( groups{m,1}, results.times_monthly );
            vals(I2,:) = groups{m,2}(I1,:);
            
            new_groups{m} = vals;
        end
        results.statistical_uncertainty.groups = new_groups;
            
    end

    % Build complete uncertainty from the two halves
    if options.ComputeStatisticalUncertainty && options.ComputeEmpiricalSpatialUncertainty
        sp = results.spatial_uncertainty;
        st = results.statistical_uncertainty;
        
        for m = 1:length(types)
            sp_unc = sp.(['unc_' types{m}]);
            st_unc = st.(['unc_' types{m}]);
            
            unc = sqrt( st_unc.^2 + sp_unc.^2 );
            
            results.(['uncertainty_' types{m}]) = unc;
        end        
    end
    
    sessionSectionEnd( 'Berkeley Average Compute Uncertainty' );    

end        

% This section generates an animated representation of the data, if
% requested.
% if options.RenderMovie
%     %%%
% end

% Save results to disk cache to accelerate any future calls usign the same
% configuration.
save( frc, hash, results );

if options.SaveResults
    target = options.OutputDirectory;
    if options.OutputPrefix
        pref = options.OutputPrefix;
        pref( pref == ' ' ) = '_';
        target = [target psep pref '.'];
    else
        target = [target psep 'results.'];
    end
    target = [target num2str(calling_records) 's.' datestr(now, 30) '.mat'];
    
    checkPath( target );
    results.file_name = target;

    save( target, 'results' );    
end

sessionSectionEnd( 'Berkeley Average' );
