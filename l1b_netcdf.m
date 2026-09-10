%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024, by the California Institute of Technology. ALL RIGHTS
% RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [savename] = l1b_netcdf(out_dat, savename, doubles_var_list, int16_var_list)
% assumes dat.atts is a structure of netcdf global attributes
VERBOSITY = 0;

%
comp_shuffle    = true; % shuffle filter (helps reduce size)
comp_deflate    = true; % Enables compression
comp_level      = 1; % 1-9, 0 disables compression

if( ~exist('doubles_var_list','var') ) % default
    doubles_var_list    = {}; % list of variables names (case-insensitive check) to make doubles instead of singles
end
if( ~exist('int16_var_list','var') ) % default
    int16_var_list    = {}; % list of variables names (case-insensitive check) to make int16 instead of singles
end

%
my_datetime_utc = datetime('now','Format','yyyyMMdd_HHmmss','TimeZone','UTC');
if VERBOSITY
    fprintf('Creating L1B NETCDF: %s\n',savename);
end
    
% create file
ncid = netcdf.create(savename,'NETCDF4');
netcdf.close(ncid);
ncid = netcdf.open(savename,'WRITE');
netcdf.reDef(ncid);

% define dimensions
f = fields(out_dat);
dims = [];
for i=1:length(f)
    if( strcmpi(f{i},'atts') )
        continue
    else
        dims = [dims size(getfield(out_dat,f{i}))];
    end
end
dims = unique(dims);
for i=1:length(dims)
    eval(sprintf("dimid(i) = netcdf.defDim(ncid,'dim%d', netcdf.getConstant('NC_UNLIMITED'));",i));
    %eval(sprintf("dimid%d = netcdf.defDim(ncid,'dim%d', dims(i));",i,i));
end

% define variables
varid = [];
for i=1:length(f)
    if( strcmpi(f{i},'atts') )
        continue
    else
        
        if( sum( strcmpi(f{i},doubles_var_list) )>0 )
            nc_type = 'NC_DOUBLE';
            fill_val =  double(NaN);
        elseif( sum( strcmpi(f{i},int16_var_list) )>0 )
            nc_type = 'NC_SHORT';
            fill_val = int16(-32767);
        else
            nc_type = 'NC_FLOAT';
            fill_val = single(NaN); 
        end

        [~,tmp] = ismember(size(getfield(out_dat,f{i})), dims);
        if tmp == 1, tmp = 1; end % For scalars
        varid(i) = netcdf.defVar(ncid, f{i}, nc_type, dimid(tmp));
        netcdf.defVarDeflate(ncid,varid(i),comp_shuffle,comp_deflate,comp_level)

        % Set the default _FillValue attribute
        netcdf.defVarFill(ncid, varid(i), false, fill_val);
    end
end
netcdf.close(ncid);
%pause(1)

% Write Variables
for i=1:length(f)
    if( strcmpi(f{i},'atts') )
        continue
    elseif( strcmpi(f{i},'var_atts') )
        continue
    else
        if( sum( strcmpi(f{i},int16_var_list) )>0 )
            ncwrite(savename,f{i}, int16(getfield( out_dat,f{i} )) );
        else
            ncwrite(savename,f{i}, getfield( out_dat,f{i} ));
        end
        % Variable attributes
        try
            tmp = getfield( out_dat.var_atts, f{i} );
            ncwriteatt(savename, f{i}, 'long_name', tmp{1});
            ncwriteatt(savename, f{i}, 'units', tmp{2});
        catch
            warning('Variable attributes for %s not found in out_dat.var_atts',f{i})
        end
    end
end

% Write Attributes
if isfield( out_dat,'atts' )
    f = fields(out_dat.atts);
    for i=1:length(f)
        tmp = getfield(out_dat.atts,f{i});
        if( islogical(tmp) )
            ncwriteatt( savename,'/',f{i}, double(tmp) )
        else
            ncwriteatt( savename,'/',f{i}, tmp )
        end
        % try
        %     ncwriteatt( savename,'/',f{i}, tmp )
        % catch
        %     f{i}
        %     tmp
        % end

        % if( size(tmp,2)>1 )
        %     for j=1:size(tmp,2)
        %         ncwriteatt( savename,'/',[f{i} num2str(j)], num2str(tmp(j,:)) );
        %     end
        % else
        %     %TBD
        % end
    end
end
ncwriteatt( savename,'/','nc_created_utc', char(my_datetime_utc) );

