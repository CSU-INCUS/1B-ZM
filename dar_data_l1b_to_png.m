%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024, by the California Institute of Technology. ALL RIGHTS
% RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function dar_data_l1b_to_png(dar_l1b_nc_path, dar_l1b_png_path, dem_path)
% dar_l1b_nc_path:  input filepath of DAR L1B data
% dar_l1b_png_path: output filepath for PNG image
% dem_path: (optional) the filepath the DEM file 'DEM_Full_Earth.mat'

if( ~exist('dem_path','var') )
    if( exist('../dem/DEM_Full_Earth.mat','file')==2 )
        dem_path = '../dem/DEM_Full_Earth.mat';
    elseif( exist('./dem/DEM_Full_Earth.mat','file')==2 )
        dem_path = '../dem/DEM_Full_Earth.mat';
    else
        dem_path = 'DEM_Full_Earth.mat';
    end
end

% TODO: The DEM path, or structure with DEM variables, should be an
%       input to the the dar_data_l1a_to_l1b()

SAVE_IMAGE  = 1;
CLOSE_IMAGE = 1;
file_path = dar_l1b_nc_path;

%%
% z_ka_meas_dbz       = ncread(file_path,'z_ka_meas_dbz');
% echo_mask           = ncread(file_path,'echo_mask');
% beam_index          = ncread(file_path,'beam_index');
% gates_lon_deg       = ncread(file_path,'gates_lon_deg');
% gates_lat_deg       = ncread(file_path,'gates_lat_deg');
% try
%     gates_alt_m         = ncread(file_path,'gates_alt_m');
% catch
%     gates_alt_m         = ncread(file_path,'gates_altitude_m');
% end
% ellipsoid_lat_deg   = ncread(file_path,'ellipsoid_lat_deg');
% ellipsoid_lon_deg   = ncread(file_path,'ellipsoid_lon_deg');
% time_j2000          = ncread(file_path,'j2000_time_sec');
%%%%% TBD
z_ka_meas_dbz       = ncread(file_path,'z_ka_meas_dbz').';
echo_mask           = ncread(file_path,'echo_mask').';
beam_index          = ncread(file_path,'beam_index').';
gates_lon_deg       = ncread(file_path,'gates_lon_deg').';
gates_lat_deg       = ncread(file_path,'gates_lat_deg').';
try
    gates_alt_m         = ncread(file_path,'gates_alt_m').';
catch
    gates_alt_m         = ncread(file_path,'gates_altitude_m').';
end
ellipsoid_lat_deg   = ncread(file_path,'ellipsoid_lat_deg').';
ellipsoid_lon_deg   = ncread(file_path,'ellipsoid_lon_deg').';
time_j2000          = ncread(file_path,'j2000_time_sec').';

m           = beam_index==4;
z_beam4     = z_ka_meas_dbz(m,:);
echo_mask4  = echo_mask(m,:);
lat_line    = gates_lat_deg(m,:);
lon_line    = gates_lon_deg(m,:);
alt_km      = gates_alt_m(m,:)/1000;
lat_deg     = ellipsoid_lat_deg(m,:);
lon_deg     = ellipsoid_lon_deg(m,:);
j2000_s     = time_j2000(m,:);    

% apply the echo mask
z_beam4(echo_mask4<1) = nan; 

% %The data can be downsampled if needed
% N_dec = 3;
% z_beam4     = z_beam4(1:N_dec:end, :);
% lat_line    = lat_line(1:N_dec:end, :);
% lon_line    = lon_line(1:N_dec:end, :);
% alt_km      = alt_km(1:N_dec:end, :);
% lat_deg     = lat_deg(1:N_dec:end,:);
% lon_deg     = lon_deg(1:N_dec:end,:);
% j2000_s     = j2000_s(1:N_dec:end,:);

%%
cmap_z = [0.952380955219269	0.761904776096344	0.571428596973419	0.380952388048172	0.190476194024086	0	0	0	0.0754901990294457	0.176143795251846	0.276797384023666	0.316309988498688	0.335442274808884	0.354574531316757	0.373706817626953	0.392839074134827	0.498468697071075	0.427258878946304	0.356049090623856	0.284839272499085	0.213629439473152	0.142419636249542	0.0712098181247711	0	0.0869565233588219	0.173913046717644	0.260869562625885	0.347826093435288	0.434782594442368	0.521739125251770	0.608695626258850	0.695652186870575	0.782608687877655	0.869565188884735	0.956521749496460	1	1	1	1	1	1	1	1	1	1	1	1	1	1	1	0.978699684143066	0.957399368286133	0.936099052429199	0.914798736572266	0.893498480319977	0.872198164463043	0.850897848606110	0.829597532749176	0.808297216892242	0.786996901035309	0.765696585178375	0.744396269321442	0.723095953464508	0.701795637607575	0.680495381355286	0.659195065498352	0.637894749641419	0.616594433784485	0.595294117927551	0.573993802070618	0.552693486213684	0.531393170356751	0.510092854499817	0.499932378530502	0.523191332817078	0.546450316905975	0.569709241390228	0.592968225479126	0.616227209568024	0.639486134052277	0.662745118141174	0.686004042625427	0.709263026714325	0.732521951198578	0.755780935287476	0.779039919376373	0.802298843860626	0.825557827949524	0.848816752433777	0.872075736522675	0.895334661006928	0.918593645095825	0.941852629184723	0.965111553668976	0.988370537757874;
          0.952380955219269	0.761904776096344	0.571428596973419	0.380952388048172	0.190476194024086	0	0	0	0.186274513602257	0.434640526771545	0.683006525039673	0.750337958335877	0.757324457168579	0.764310956001282	0.771297454833984	0.778283953666687	0.803618609905243	0.759964406490326	0.716310203075409	0.672655999660492	0.629001796245575	0.585347592830658	0.541693389415741	0.498039215803146	0.541687965393066	0.585336744785309	0.628985524177551	0.672634243965149	0.716283023357391	0.759931802749634	0.803580582141876	0.847229301929474	0.890878081321716	0.934526860713959	0.978175640106201	0.965517222881317	0.896551728248596	0.827586233615875	0.758620679378510	0.689655184745789	0.620689630508423	0.551724135875702	0.482758611440659	0.413793116807938	0.344827592372894	0.275862067937851	0.206896558403969	0.137931033968925	0.0689655169844627	0	0.00776057830080390	0.0155211566016078	0.0232817344367504	0.0310423132032156	0.0388028919696808	0.0465634688735008	0.0543240457773209	0.0620846264064312	0.0698451995849609	0.0776057839393616	0.0853663608431816	0.0931269377470017	0.100887514650822	0.108648091554642	0.116408668458462	0.124169252812862	0.131929829716682	0.139690399169922	0.147450983524323	0.155211567878723	0.162972137331963	0.170732721686363	0.178493291139603	0.182195186614990	0.173720985651016	0.165246784687042	0.156772598624229	0.148298397660255	0.139824211597443	0.131350010633469	0.122875817120075	0.114401623606682	0.105927430093288	0.0974532365798950	0.0889790430665016	0.0805048495531082	0.0720306560397148	0.0635564550757408	0.0550822652876377	0.0466080680489540	0.0381338745355606	0.0296596810221672	0.0211854856461287	0.0127112921327353	0.00423709722235799;
          0.952380955219269	0.761904776096344	0.571428596973419	0.380952388048172	0.190476194024086	0	0.855263173580170	0.971052646636963	0.983333349227905	0.961111128330231	0.938888907432556	0.914147317409515	0.888565957546234	0.862984657287598	0.837403297424316	0.811821937561035	0.541192054748535	0.463878929615021	0.386565774679184	0.309252619743347	0.231939464807510	0.154626309871674	0.0773131549358368	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0	0.0234468542039394	0.0468937084078789	0.0703405588865280	0.0937874168157578	0.117234267294407	0.140681117773056	0.164127975702286	0.187574833631516	0.211021676659584	0.234468534588814	0.257915377616882	0.281362235546112	0.304809093475342	0.328255951404572	0.351702809333801	0.375149667263031	0.398596495389938	0.422043353319168	0.445490211248398	0.468937069177628	0.492383927106857	0.515830755233765	0.539277613162994	0.561956286430359	0.582330405712128	0.602704524993897	0.623078703880310	0.643452823162079	0.663826942443848	0.684201061725617	0.704575181007385	0.724949300289154	0.745323419570923	0.765697538852692	0.786071658134460	0.806445837020874	0.826819956302643	0.847194075584412	0.867568194866180	0.887942314147949	0.908316433429718	0.928690552711487	0.949064671993256	0.969438791275024	0.989812910556793].';

%% Load the DEM
try
   if( ~exist('topo30_dem','var') || ~exist('topo30_lat','var') || ~exist('topo30_lon','var') )
        %%% Option 1
        % % topo30 format
        % % The  subdirectory called topo30 has the data stored in a single large file of 2-byte integers
        % % in MSB format (i.e. big-endian).  The grid spans 0 to 360 in longitude and -90 to 90 in latitude. 
        % % The upper left corner of the upper left grid cell has latitude 90 and longitude 0.  There are 
        % % 43200 columns and 21600 rows. 
        % defs.dem_name = "SRTM30 Plus V11 - https://topex.ucsd.edu/pub/srtm30_plus/topo30/";
        % fid         = fopen('./srtm30/topo30','rb');
        % topo30_dem  = fread(fid, [43200 21600], 'int16','ieee-be');
        % fclose(fid);
        % topo30_dem  = flipud(topo30_dem.');
        % topo30_lat  = linspace(-90,90,21600);
        % topo30_lon  = linspace(0,360,43200+1);
        % topo30_dem  = [topo30_dem topo30_dem(:,1)]; % add the 0/360 line to the end to ensure the interpolation finds data for the last 1km in longitude

        %%% Option 2
        defs.dem_name   = "SRTM based 1km DEM";
        tmp             = load(dem_path); % DEM in meters now in B_cat
        topo30_dem = [tmp.B_cat tmp.B_cat(:,1)];
        topo30_lat = tmp.lat_plot;
        topo30_lon = [tmp.lon_plot tmp.lon_plot(1)+360];
        % Order the DEM from 0 to 360 deg longitude
        ind = find(topo30_lon<0,1,'last');
        topo30_dem = [topo30_dem(:,ind+1:end) topo30_dem(:,1:ind)];
        topo30_lon = [topo30_lon(:,ind+1:end) topo30_lon(:,1:ind)+360];
    end
    DEM_FOUND = 1;
catch
    warning('No DEM found!')
    defs.dem_name = "No DEM found.";
    DEM_FOUND = 0;
end

% assume 0-360 deg
lon_deg(lon_deg<0) = lon_deg(lon_deg<0)+360;

% Subset and downsample the DEM
m = topo30_lat>=-40 & topo30_lat<=40;
dem.h       = topo30_dem(m,:);
dem.lat     = topo30_lat(m);
dem.lon     = topo30_lon;
D_dem = 10;
dem.h       = dem.h(1:D_dem:end,1:D_dem:end)-1; % The -1 is to get the colorscale to work right for the ocean
dem.lat     = dem.lat(1:D_dem:end);
dem.lon     = dem.lon(1:D_dem:end);

%% PLOTTING ---
inds        = 1:size(lon_deg,1);
D_tick      = floor(length(lon_deg)/10);
xtick_ind   = [1, D_tick:D_tick:length(lon_deg)-(D_tick/2), length(lon_deg)];

alt_km(~isfinite(alt_km)) = 0;

figid = figure('position',[50 50 1500 650]);
clf
ax = subplot(2,1,1);
pcolor(repmat(inds.',1,size(alt_km,2)),alt_km,z_beam4)
%pcolor(z_beam4)
colormap(cmap_z)
clim([10 70])
ylim([-1 20])
colorbar
shading flat
hold on
plot(1,                         min(ylim()),'ko','linewidth',2,'MarkerSize',7,'HandleVisibility','off')
plot(length(lon_deg),            min(ylim()),'kd','linewidth',2,'MarkerSize',7,'HandleVisibility','off')
plot(xtick_ind(2:end-1),    min(ylim())*ones(1,length(xtick_ind)-2),'kx','linewidth',2,'MarkerSize',7,'HandleVisibility','off')
hold off
grid on
ylabel('Altitude (km)')
title(['Beam 4 Reflectivity (dBZ)'])
set(gca,'XTick',xtick_ind)
ix = get(gca,'XTick');
dt = j2000_tai_sec_to_utc_datetime(j2000_s(ix));
%str = string( dt )
str = {};
for i = 1:length(dt)
    str{i} = sprintf('%s\\newline%s UTC', string(dt(i), 'yyyy-MM-dd'), string(dt(i), 'HH:mm:ss'));
end
set(gca,'XTickLabel',str,'XTickLabelRotation',0);

ax = subplot(2,1,2);
pcolor(dem.lon,dem.lat,dem.h)
shading flat
[cmap1,climits] = demcmap([-10000 7000],200);
colormap(ax,cmap1(101:end,:))
clim([diff(climits)/2 + climits(1) climits(2)] )
colorbar
axis image
%caxis([0 7000])
hold on
ind = find( abs(diff(lon_deg)) > 100);

if( isempty(ind) )
    plot(lon_deg,lat_deg,'r','linewidth',4)
else
    for i = 0:length(ind)
        if(i==0)
            plot(lon_deg(1:ind(i+1)),lat_deg(1:ind(i+1)),'r','linewidth',4)
        elseif(i==length(ind))
            plot(lon_deg((ind(i)+1):end),lat_deg((ind(i)+1):end),'r','linewidth',4)
        else
            plot(lon_deg((ind(i)+1):ind(i+1)),lat_deg((ind(i)+1):ind(i+1)),'r','linewidth',4)
        end
    end
end
plot(lon_deg(1), lat_deg(1),'ko','linewidth',3,'MarkerSize',10)
plot(lon_deg(end), lat_deg(end),'kd','linewidth',3,'MarkerSize',10)
plot(lon_deg(xtick_ind(2:end-1)), lat_deg(xtick_ind(2:end-1)),'kx','linewidth',3,'MarkerSize',10)
if( isempty(ind) )
    plot(lon_deg,lat_deg,'k--','linewidth',1)
else
    for i = 0:length(ind)
        if(i==0)
            plot(lon_deg(1:ind(i+1)),lat_deg(1:ind(i+1)),'k--','linewidth',1)
        elseif(i==length(ind))
            plot(lon_deg((ind(i)+1):end),lat_deg((ind(i)+1):end),'k--','linewidth',1)
        else
            plot(lon_deg((ind(i)+1):ind(i+1)),lat_deg((ind(i)+1):ind(i+1)),'k--','linewidth',1)
        end
    end
end
hold off
xlabel('Longitude (deg)')
ylabel('Latitude (deg)')
title(['Ground Track over DEM (meters)'])

if( SAVE_IMAGE )
    fprintf('Saving PNG: %s\n',dar_l1b_png_path)
    set(gcf,'PaperPositionMode','auto')
    print(dar_l1b_png_path,'-r300','-dpng')
    if( CLOSE_IMAGE )
        close(figid)
    end
end


