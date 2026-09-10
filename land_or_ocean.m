function is_ocean = land_or_ocean(lat,lon,coast_data)
% returns 1 for ocean, 0 for land

% adapted from: https://www.mathworks.com/matlabcentral/answers/1065-determining-whether-a-point-on-earth-given-latitude-and-longitude-is-on-land-or-ocean

SHOW_DEBUG_PLOTS = 0;

if( ~exist('coast_data','var') )
    coast_data = load('coastlines.mat');
end
[Z, R] = vec2mtx(coast_data.coastlat, coast_data.coastlon,1, [-90 90], [-90 270], 'filled');
is_ocean = geointerp(Z, R, lat, lon) == 2;

if( SHOW_DEBUG_PLOTS )
    figure; worldmap(Z, R)
    geoshow(Z, R, 'DisplayType', 'texturemap')
    colormap([0 1 0;0 0 0;0 1 0;0 0 1])
    lat = 38.53;%N
    lon = -57.07;%W
    plotm(lat,lon,'ro')
end