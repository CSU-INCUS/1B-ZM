%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024-2026, by the California Institute of Technology. ALL 
% RIGHTS RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Assumes the reflectivity profile is clear air and includes the surface

% to avoid dealing with pulse vs. beam limited checks, we're going to
% sum all range bins over a certain reflectivity/SNR 

% we should check that there are range gates that are "clear" at the end
% and the surface doesn't fall outside the sampled range line

function [uncorrected_sigma0_db, z_peak_dbz, rng_mean_m, rng_width_m, mask_surface_at_edge, num_gates_valid] = ...
    radar_surface_response(defs, z_dbz, rng_m, noise_equiv_dbz, mainlobe_power_from_peak_db, min_snr_db)
% defs is a structure with fields: 
%           lambda0: wavelength (m)
%           Kw2: dielectric factor of water
%           range_res_m: range resolution (m)
% z_db : profiles x gates
% rng_m : profiles x gates
% noise_equiv_dbz : profiles x 1
% range_res_m: 1x1
% mainlobe_power_from_peak_db : 1x1
% min_snr_db : 1x1

% We're summing all the echo power into one gate to treat it as if it's
% beam-limited.  We also assume the footprint area (and NRCS) are constant 
% over the range of pointing angles evaluated.

if( ~exist('mainlobe_power_from_peak_db','var') )
    mainlobe_power_from_peak_db = 20;
end
if( ~exist('min_snr_db','var') )
    min_snr_db  = 10;
end

% Some constants
lambda          = defs.c0/defs.f_Hz;
Kw2             = defs.Kw2;
range_res_m     = defs.range_res_m;

% apply data masks and calculate power, range centroid, range width
[z_peak_dbz,~]  = max(z_dbz,[],2);
m               = z_dbz>repmat(z_peak_dbz-mainlobe_power_from_peak_db, 1, size(z_dbz,2)) & z_dbz>repmat(noise_equiv_dbz+min_snr_db, 1, size(z_dbz,2));
z_r             = 10.^(z_dbz./10);
z_r(~m)         = 0;
p               = sum( z_r,2,'omitnan' );
rng_mean_m      = sum( z_r.* (rng_m),2,'omitnan' )./ p;
rng_width_m     = sqrt(sum( z_r.*(rng_m-repmat(rng_mean_m,1,size(z_r,2))).^2,2,'omitnan' ) ./ p);

% The sigma0 estimate from measured reflectivity (doesn't correct for 
% attenuation, pulse-compression filter loss, etc. and assumes pulse range 
% res is the range gate sampling, which is not true). 
% There is some variation in the summed power given a 20 dB threshold on 
% the pattern/echo, and this varies as the SNR check influences the data 
% used. With the 20 dB threshold, this could result in a Sigma0 that is 
% 0.43 dB higher with a Gaussian beam than the V6 footprint would suggest.
% The range resolution that is used in the weather radar constant should be
% used here (to convert the V6 volume calculation back to a surface area
% calculation).
uncorrected_sigma0_db = 10*log10(p) + 10*log10(range_res_m) - 10*log10(10^18*lambda.^4./(pi^5*Kw2));

% Look for the peak to be close to the edge, biases range width
mask_surface_at_edge    = m(:,1)==1 | m(:,2)==1 | m(:,end-1)==1 | m(:,end)==1;
num_gates_valid         = sum(m,2); 



