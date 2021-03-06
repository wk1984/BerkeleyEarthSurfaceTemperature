function se = compress( se )
% Compress stationElement into a compact memory representation.

persistent minMemSize;
if isempty(minMemSize)
    zm = zipMatrix;
    minMemSize = memSize(zm);
end

if ~isa( se.dates, 'zipMatrix' )
    if isa( se.dates, 'compactVector' )
        se.dates = expand( se.dates );
    end
    if ~isa( se.dates, 'uint32' )
        se.dates = uint32( se.dates );
    end
    if minMemSize < 4*length(se.dates)        
        dt = zipMatrix( se.dates );
        if memSize( dt ) < 4*length(se.dates)
            se.dates = dt;
        end
    end
end

if ~isa( se.time_of_observation, 'zipMatrix' )
    if isa( se.time_of_observation, 'compactVector' )
        se.time_of_observation = double( se.time_of_observation );
    end
    if ~isa( se.time_of_observation, 'uint8' )
        f = isnan( se.time_of_observation );
        se.time_of_observation(f) = 255;
        se.time_of_observation = uint8( se.time_of_observation );
    end
    if minMemSize < length( se.time_of_observation )        
        tob = zipMatrix( se.time_of_observation );
        if memSize( tob ) < length( se.time_of_observation )
            se.time_of_observation = tob;
        end
    end
end

if ~isa( se.data, 'zipMatrix' )
    if isa( se.data, 'compactVector' )
        se.data = double( se.data );
    end
    if ~isa( se.data, 'single' )
        se.data = single( se.data );
    end
    if minMemSize < 4*length(se.data)        
        rd = zipMatrix( se.data );
        if memSize( rd ) < 4*length(se.data)
            se.data = rd;
        end
    end
end

if ~isa( se.num_measurements, 'zipMatrix' )
    if isa( se.num_measurements, 'compactVector' )
        se.num_measurements = double( se.num_measurements );
    end
    if ~isa( se.num_measurements, 'uint16' )
        f = isnan( se.num_measurements );
        se.num_measurements(f) = 65535;
        se.num_measurements = uint16( se.num_measurements );
    end
    if minMemSize < 2*length( se.num_measurements )        
        nm = zipMatrix( se.num_measurements );
        if memSize( nm ) < 2*length( se.num_measurements )
            se.num_measurements = nm;
        end
    end
end

if ~isa( se.source, 'zipMatrix' )
    if isa( se.source, 'compactVector' )
        se.source = double( se.source );
    end
    if ~isa( se.source, 'uint8' )
        f = isnan( se.source );
        se.source(f) = 0;
        se.source = uint8( se.source );
    end
    if minMemSize < length(se.source)        
        nm = zipMatrix( se.source );
        if memSize( nm ) < length(se.source)
            se.source = nm;
        end
    end
end

if ~isa( se.flags, 'zipMatrix' )
    if isa( se.flags, 'compactVector' )
        se.flags = double( se.flags );
    end
    if ~isa( se.flags, 'uint16' )
        f = isnan( se.flags );
        se.flags(f) = 0;
        se.flags = uint16( se.flags );
    end
    if minMemSize < 2*length(se.flags)        
        nm = zipMatrix( se.flags );
        if memSize( nm ) < 2*length(se.flags)
            se.flags = nm;
        end
    end
end