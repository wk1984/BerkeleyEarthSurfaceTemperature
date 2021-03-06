function display( ss )

if length(ss) > 1
    display( ['  ' num2str(length(ss)) ' StationSites'] );
    return;
end

global country_names_dictionary

if isempty( country_names_dictionary )
    [~, country_names_dictionary] = loadCountryCodes;
end

stationSite = struct();
stationSite.id = ss.id;
stationSite.name = ss.primary_name;
if ~isempty(ss.alt_names)
    stationSite.alt_names = ss.alt_names;
end

if length(ss.country) > 1
    stationSite.country = 'Conflict';
elseif ss.country > 0
    stationSite.country = country_names_dictionary( ss.country );
else
    stationSite.country = '[Missing]';
end

if ~isempty(ss.state)
    stationSite.state = ss.state;
end
if ~isempty(ss.county)
    stationSite.county = ss.county;
end
stationSite.other_ids = ss.other_ids;
stationSite.lat = ss.location.lat;
stationSite.long = ss.location.long;
stationSite.elev = ss.location.elev;
stationSite.sources = ss.sources;
stationSite.uids = ss.associated_uids;

display(stationSite)