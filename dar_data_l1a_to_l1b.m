%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024-2026, by the California Institute of Technology. ALL 
% RIGHTS RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% DAR L1A-PWR to DAR L1B-ZM Processor
%
% v0.01:    Initial release, prototype version
% v0.1:     First test with full orbit file (supports example .mat input)
% v0.11:    Added timing display in sections
% v0.2:     Updated output variable names. Added reflectivity estimate with 
%           noise correction. Include range migration estimate and 
%           compensation. Added echo mask and sigma0 estimates. Added DAR 
%           IDs and cal parameters.  
% v0.3:     Removed the debug/test "INPUT_DATA_MODE" flag from the code
%           Revised quaternions for geolocation and tested with simulation.
%           Updated noise estimation to use histogram over small AT domain and then a second over a longer AT domain. It may still shows some bias in precipitation (0.1-0.2 dB).
%           The "Low SNR" threshold was revised based on the simulations results. 
%           The sigma0 estimate correction factor was also emperically estimated from the simulated data.
% v0.4:     modified inputs field to use a structure 'opts' for the SHOW_PLOT, ERROR_CHECK, and DAR_SYSTEM_ID with defaults
%           added a check to estimate the DAR_SYSTEM_ID from the PRE-LAUNCH waveform CRC if it's not provided by the user in opts.
%           added the definition of the NetCDF variable attributed for long name and units.
%           Updated the DEM model used for DEM height estimates (smaller file size, lower res--1km, no bathymetry, limited latitude range)
% v0.4.1:   Modified DEM file location to be in parallel ../dem/ directory rather than a subdirectory ./dem/
% v0.5:     Added DAR_SYSTEM_ID definitions for the 110us pulses
% v0.6:     Added opts.dem_path input arg for the user to define the DEM files location, with a default to check of the local directories to find the DEM file
% v1.0:     Added beam-dependent antenna gains to "def" stucture for the radar constant. 
%           Updated beam pointing for all FM DARS
%           Added comments and descriptions for the source of different the DAR system parameters.
%           Updated dem_name attribute to include the path and name.
% v1.01     Added DAR to body relative quaternions and automatic filename generation.
%           Cleaned up console output display
% v1.02     Add required root metadata per CF1.11
%
% INPUT:
% - dar_l1a_nc_path:        Input filepath of DAR L1A-PWR data (.nc)
% - sc_l1a_path:            Input filepath of L1A-SC data (.nc)
% - dar_l1b_out_path:       (OPTIONAL) Output filepath for DAR L1B-ZM data. If empty, it will automatically generate filename in the root directory
% - opts:                   (OPTIONAL) Optional inputs 
%       opts.SHOW_PLOT:     for debug (default is 0)
%       opts.ERROR_CHECK:   enables additional data checks for potential errors/irregularities (default is 0)
%       opts.DAR_SYSTEM_ID: The DAR calibration/config to used for processing (default is to determine the ID from the Waveform's CRC)
%       opts.dem_path:      The filepath of the DEM file 'DEM_Full_Earth.mat' (default is to look for it in ../dem/ ./dem/ and ./)
%
% OUTPUT: (see API for complete updated list of products)
% - L1B-ZM data (.nc):
%             L1A-PWR data that has been calibrated and geolocated
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [savename] = dar_data_l1a_to_l1b(dar_l1a_nc_path, sc_l1a_path, dar_l1b_out_path, opts)
%% Constants and metadata %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
version_l1b = '1.02';

console_message(sprintf("Starting dar_data_l1a_to_l1b. Version: %s", version_l1b)); fprintf("\n");
if( ~exist('opts','var') )
    opts = [];
end
dem_name = "SRTM based 1km DEM";
if( ~isfield(opts,'dem_path') )
    if( exist('../dem/DEM_Full_Earth.mat','file')==2 )
        dem_path = '../dem/DEM_Full_Earth.mat';
    elseif( exist('./dem/DEM_Full_Earth.mat','file')==2 )
        dem_path = '../dem/DEM_Full_Earth.mat';
    else
        dem_path = 'DEM_Full_Earth.mat';
    end
else
    dem_path = opts.dem_path;
end
if( isfield(opts,'DAR_SYSTEM_ID') )
    DAR_SYSTEM_ID = opts.DAR_SYSTEM_ID;
end
if( isfield(opts,'SHOW_PLOT') )
    SHOW_PLOT = opts.SHOW_PLOT;
else
    SHOW_PLOT = 0;
end
if( isfield(opts,'ERROR_CHECK') )
    ERROR_CHECK = opts.ERROR_CHECK;
else
    ERROR_CHECK = 0;
end

%% Import L1A DAR data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_read_l1a = tic;
console_message("Reading L1A data");

nci = ncinfo(dar_l1a_nc_path);
f = {nci.Variables.Name};
dat = struct();
for i=1:length(f)
    dat.(f{i}) = ncread(dar_l1a_nc_path, f{i});
end

f = {nci.Attributes.Name};
dat.atts = struct();
for i=1:length(f)
    dat.atts.(f{i}) = ncreadatt(dar_l1a_nc_path,'/',f{i});
end
% end
clearvars f nci

fprintf("%.2f seconds\n", toc(t_read_l1a));

%% Estimate the DAR_SYSTEM_ID
if( ~exist('DAR_SYSTEM_ID','var') )
    % Get the waveform crc data 
    waveform_crc = unique( dat.cal_waveform_bram_crc );
    waveform_crc_sys_id_list = [
            % CRC, DAR_SYSTEM_ID
            16132, 0007;    % A simulation/test case
            0xa49c, 0003; % 130us, FM3
            0x982e, 0002; % 130us, FM2
            0xee50, 0001; % 130us, FM1
            0x0ffc, 0103; % 110us, FM3
            0x4e31, 0102; % 110us, FM2
            0x7647, 0101; % 110us, FM1
        ];
    
    if( length(waveform_crc)~=1 )
        DAR_SYSTEM_ID = -1;
        error('Multiple Waveform CRCs in file! User should select configuration for processing.')
    end
    ind = find(waveform_crc == waveform_crc_sys_id_list(:,1));
    if( isempty(ind) )
        DAR_SYSTEM_ID = -1;
        error('Waveform CRC does not match available list! User should select configuration for processing.')
    elseif( length(ind)>1 )
        DAR_SYSTEM_ID = -1;
        error('Waveform CRC has multiple matches in the available list! Check the list or the user should select configuration for processing.')
    else
        DAR_SYSTEM_ID = waveform_crc_sys_id_list(ind);
    end
end

%%
% The FPGA version should be fixed constant for DAR
fpga_version = unique( dat.tel_fpga_version );
if( length(fpga_version)>1 && ERROR_CHECK )
    error('Multiple FPGA versions found')
elseif( fpga_version~=0x30 && ERROR_CHECK )
    error('FPGA version does not match expected version.')
end

% Checks for the radar parameters
if( length( unique( dat.sci_pri_length ) )>1 && ERROR_CHECK )
    error('Multiple PRI detected!')
end
if( length( unique( dat.sci_rx_window_avg_count ) )>1 && ERROR_CHECK )
    error('Multiple average counts found')
end

%% Import L1A SC data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_read_sc = tic;
console_message("Reading SC data");

sc  = import_sc1a_data(sc_l1a_path);

fprintf("%.2f seconds\n", toc(t_read_sc));

%% Set a static config with all constants %%%%%%%%%%%%%%%%%%%%%%%%%
t_import_config = tic;
console_message("Setting DAR configuration");

defs.c0                             = 299792458;
defs.f_Hz                           = 35.75e9;
defs.Kw2                            = 0.91;
defs.fs                             = 2.5e6;
defs.clk_period                     = 1/40e6;
defs.beam_sel_to_att_ind            = [1:7].'; 
defs.noise_window_at_samples        = 100; % This is +/-
defs.range_offset_m                 = 0; % This can be overridden later by DAR_SYSTEM_ID if needed

%% DAR model specific parameters that are static throughout the mission (these may be overridden in the parameter specific configs if needed)
% DAR_SYSTEM_ID's least-significant digit is the DAR model (1, 2, or 3)
% DAR_SYSTEM_ID's 3 (or 2) most-significant digits are different configurations

%%% Description of the key definition parameters that could change per DAR_SYSTEM_ID 
% defs.beam_attitude_deg            % beam AZ, EL, 0 angles (deg) (each row x one columns per beam)
% defs.beam_rc_correction_db        % by be radar constant correction, per beam (this is [7x1])
% defs.waveform_fc_hz               % The transmit waveform's center frequency
% defs.rcrf_fc_hz                   % The pulse compression filter's center frequency
% defs.bandwidth_mhz                % The nominal waveform/filter bandwidth
% defs.range_res_m                  % The nominal compressed range resolution (only used to record to NETCDF)
% defs.is_cal_loopback              % The end index in the calibration loopback data that will be used to 
%                                   % estimate the mean/average calloop signal power. Nominally fixed, but
%                                   % could change.
% defs.ie_cal_loopback              % The end index in the calibration loopback data that will be used to 
%                                   % estimate the mean/average calloop signal power.   Pulse length dependent.
% defs.reference_loopback_power_db  % The mean/average power expected over the loopback (between is_cal_loopback 
%                                   % and ie_cal_loopback) that was used for the radar_const_db estimate.  The actual 
%                                   % loopback power will be used to correct for drift.
% defs.cal_temp_scale_db            % A temperature compensation factor (based on the reported DCA1 temperature)
% defs.radar_const_ref_rng_m        % a reference range where the radar constant was calculated (@ 577 km range)
% defs.radar_const_db               % The compressed digital signal "echo power" to dBZ radar constant factor, referenced to 35C DCA temp

defs.beam_attitude_nominal_deg = [ % beam AZ/EL angles (deg)
    [-0.23, -1.20, +0.00]; % Beam #1
    [+0.35, -1.00, +0.00]; % Beam #2
    [-0.12, -0.60, +0.00]; % Beam #3
    [+0.00, +0.00, +0.00]; % Beam #4
    [+0.12, +0.60, +0.00]; % Beam #5
    [-0.35, +1.00, +0.00]; % Beam #6
    [+0.23, +1.20, +0.00]; % Beam #7
    ];

if( DAR_SYSTEM_ID<0 ) %ERROR
    error('Invalid DAR_SYSTEM_ID! Update L1B code with latest table or provide user-defined DAR_SYSTEM_ID.')
elseif( mod(DAR_SYSTEM_ID,10)==1 ) %%%%%% DAR FM1 -- See notes above for lineage
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [+0.111, -1.306, +0.00]; % Beam #1
        [-0.486, -1.122, +0.00]; % Beam #2
        [-0.029, -0.709, +0.00]; % Beam #3
        [-0.169, -0.118, +0.00]; % Beam #4
        [-0.308, +0.477, +0.00]; % Beam #5
        [+0.144, +0.896, +0.00]; % Beam #6
        [-0.451, +1.074, +0.00]; % Beam #7
        ];
    defs.beam_rc_correction_db = [0.99, 0.40, -0.55, -0.96, -0.24, 1.08, 1.60].';
elseif( mod(DAR_SYSTEM_ID,10)==2 ) %%%%%% DAR FM2 -- See notes above for lineage
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [+0.184, -1.962, +0.00]; % Beam #1
        [-0.422, -1.765, +0.00]; % Beam #2
        [+0.045, -1.357, +0.00]; % Beam #3
        [-0.093, -0.759, +0.00]; % Beam #4
        [-0.227, -0.160, +0.00]; % Beam #5
        [+0.235, +0.523, +0.00]; % Beam #6
        [-0.362, +0.439, +0.00]; % Beam #7
        ];
        defs.beam_rc_correction_db = [1.71, 1.18, 0.10, -0.66, -0.25, 0.77, 1.13].';
elseif( mod(DAR_SYSTEM_ID,10)==3 ) %%%%%% DAR FM3 -- See notes above for lineage
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [-0.080, -0.994, +0.00]; % Beam #1
        [-0.672, -0.803, +0.00]; % Beam #2
        [-0.212, -0.394, +0.00]; % Beam #3
        [-0.343, +0.202, +0.00]; % Beam #4
        [-0.476, +0.801, +0.00]; % Beam #5
        [-0.006, +1.220, +0.00]; % Beam #6
        [-0.618, +1.405, +0.00]; % Beam #7
        ];
        defs.beam_rc_correction_db = [2.16, 1.74, 0.27, -0.46, 0.03, 0.74, 1.24].';
elseif( mod(DAR_SYSTEM_ID,10)==7 ) %%%%%% DAR Sim "FM1 postenv asbuilt"
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [+0.0880, +1.2000, +0.00]; % Beam #1
        [-0.5040, +1.0160, +0.00]; % Beam #2
        [-0.0520, +0.6080, +0.00]; % Beam #3
        [-0.1920, +0.0160, +0.00]; % Beam #4
        [-0.3280, -0.5760, +0.00]; % Beam #5
        [+0.1240, -0.9920, +0.00]; % Beam #6
        [-0.4720, -1.1720, +0.00]; % Beam #7
        ];
    defs.beam_rc_correction_db = zeros(7,1);
    warning('SIMULATED DAR SELECTED')
elseif( mod(DAR_SYSTEM_ID,10)==8 ) %%%%%% DAR Sim "FM3 postenv asbuilt"
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [-0.0800, +0.9880, +0.00]; % Beam #1
        [-0.6720, +0.8000, +0.00]; % Beam #2
        [-0.2120, +0.3880, +0.00]; % Beam #3
        [-0.3400, -0.2040, +0.00]; % Beam #4
        [-0.4720, -0.8000, +0.00]; % Beam #5
        [-0.0040, -1.2200, +0.00]; % Beam #6
        [-0.6080, -1.4040, +0.00]; % Beam #7
        ];
    defs.beam_rc_correction_db = zeros(7,1);
    warning('SIMULATED DAR SELECTED')
elseif( mod(DAR_SYSTEM_ID,10)==9 ) %%%%%% DAR Sim "FM1 postenv asbuilt"
    defs.beam_attitude_deg = [ % beam AZ/EL angles (deg)
        [+0.0880, +1.2000, +0.00]; % Beam #1
        [-0.5040, +1.0160, +0.00]; % Beam #2
        [-0.0520, +0.6080, +0.00]; % Beam #3
        [-0.1920, +0.0160, +0.00]; % Beam #4
        [-0.3280, -0.5760, +0.00]; % Beam #5
        [+0.1240, -0.9920, +0.00]; % Beam #6
        [-0.4720, -1.1720, +0.00]; % Beam #7
        ];
    defs.beam_rc_correction_db = zeros(7,1);
    warning('SIMULATED DAR SELECTED')
else
    error('Unknown DAR model')
end

% Calculate per-beam quaternion (relative to dar frame)
% Removes beam 4 offset (if any)
t_beam_attitude_deg = defs.beam_attitude_deg - defs.beam_attitude_deg(4,:);
% Find rotation between measured and nominal
[U, ~, V]     = svd(-t_beam_attitude_deg' * defs.beam_attitude_nominal_deg);
R             = V * U';
yaw   = atan2(R(2,1),R(1,1)); % yaw = 0*pi/180; % yaw = -0.9*pi/180; % yaw = 13*pi/180;
pitch = -t_beam_attitude_deg(:,2) * pi / 180;
roll  = -t_beam_attitude_deg(:,1) * pi / 180; 
% Create roll-pitch-yaw quaternion
q_beam_wrt_dar = quaternion([yaw*ones(size(roll)) pitch roll], "euler", "zyx", "frame");

%% Parameter specific configurations
switch( DAR_SYSTEM_ID )
    case {0007, 0008, 0009} % For simulated radar testing only!
        % DAR Sim
        defs.waveform_fc_hz                 = 5e6;
        defs.rcrf_fc_hz                     = 5e6 + 6.5809e4;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 1;
        defs.ie_cal_loopback                = 1;
        defs.reference_loopback_power_db    = 0;
        defs.cal_temp_scale_db              = 0;
        defs.radar_const_ref_rng_m          = 530e3; % @ 577 km range
        defs.radar_const_db                 = 0 + defs.beam_rc_correction_db; % for each beam, at defs.radar_const_ref_rng_m 
        DAR_SYSTEM_ID = DAR_SYSTEM_ID - 6; % Convert SIM ID to a more typical ID (needed for filename)
    case 0001
        % DAR1, 130 us pulse
        defs.waveform_fc_hz                 = 4.936e6;
        defs.rcrf_fc_hz                     = 5e6;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 10;
        defs.ie_cal_loopback                = 332;
        defs.reference_loopback_power_db    = 82.1;% The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 0.8;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = -46.56 + defs.beam_rc_correction_db; % for each beam, at defs.radar_const_ref_rng_m 
    case 0002
        % DAR2, 130 us pulse
        defs.waveform_fc_hz                 = 4.936e6;
        defs.rcrf_fc_hz                     = 5e6;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 10;
        defs.ie_cal_loopback                = 332;
        defs.reference_loopback_power_db    = 81.3; % @35C % The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 0.6;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = -45.27 + defs.beam_rc_correction_db; % for each beam, 130 us pulse w/ 2.2 dB filter loss @ 577 km range
    case 0003
        % DAR3, 130 us pulse
        defs.waveform_fc_hz                 = 4.936e6; 
        defs.rcrf_fc_hz                     = 5e6; 
        defs.bandwidth_mhz                  = 2;   
        defs.range_res_m                    = 120; 
        defs.is_cal_loopback                = 10;  
        defs.ie_cal_loopback                = 332; 
        defs.reference_loopback_power_db    = 80.0; % The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 1.25;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = -45.22 + defs.beam_rc_correction_db; % for each beam, at defs.radar_const_ref_rng_m
    case 0101
        % DAR1, 110 us pulse
        defs.waveform_fc_hz                 = 4.936e6;
        defs.rcrf_fc_hz                     = 5e6;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 10;
        defs.ie_cal_loopback                = 282;
        defs.reference_loopback_power_db    = 82.1; % The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 0.8;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = (-46.56 + 10*log10(130/110)) + defs.beam_rc_correction_db; % for each beam, at defs.radar_const_ref_rng_m 
    case 0102
        % DAR2, 110 us pulse
        defs.waveform_fc_hz                 = 4.936e6;
        defs.rcrf_fc_hz                     = 5e6;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 10;
        defs.ie_cal_loopback                = 282;
        defs.reference_loopback_power_db    = 81.3; % @35C % The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 0.6;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = (-45.27 + 10*log10(130/110)) + defs.beam_rc_correction_db; % for each beam, 130 us pulse w/ 2.2 dB filter loss @ 577 km range
    case 0103
        % DAR3, 110 us pulse
        defs.waveform_fc_hz                 = 4.936e6;
        defs.rcrf_fc_hz                     = 5e6;
        defs.bandwidth_mhz                  = 2;
        defs.range_res_m                    = 120;
        defs.is_cal_loopback                = 10;
        defs.ie_cal_loopback                = 282;
        defs.reference_loopback_power_db    = 80.0; % The mean power over the loopback, so TBP is in radar_const_db...
        defs.cal_temp_scale_db              = 1.25;
        defs.radar_const_ref_rng_m          = 577e3; % @ 577 km range
        defs.radar_const_db                 = (-45.22 + 10*log10(130/110)) + defs.beam_rc_correction_db; % for each beam, at defs.radar_const_ref_rng_m
    otherwise
        error('Unknown DAR_SYSTEM_ID')
end

%%% Calculated values
defs.range_sample_m = defs.c0/defs.fs/2; 
lambda              = defs.c0 / defs.f_Hz;
N_sci_ave           = unique( double(dat.sci_rx_window_avg_count) + 1 );

fprintf("%.2f seconds\n", toc(t_import_config));

%% Pre-processing %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_preproc = tic;
console_message("Pre-processing");

% Time Estimates %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
time.t_start_j2000      = min(dat.calc_sci_time);
time.t_end_j2000        = max(dat.calc_sci_time);
time.t_rel              = dat.calc_sci_time - time.t_start_j2000;
% Get dimensions of the science data
N_profile           = size(dat.calc_sci_echo_db,1);
N_gate              = size(dat.calc_sci_echo_db,2);
def.N_profile       = N_profile;
def.N_gate          = N_gate;

time.t_start_utc = [char( j2000_tai_sec_to_utc_datetime(time.t_start_j2000) ) ' UTC'];

% Error checks, etc.
% monotonic, no large jumps (more than an orbit?), "regular" sampling, etc.
if( sum(diff(dat.calc_sci_time)<0) && ERROR_CHECK )
    error('DAR science packets have non-monotonicly increasing times!')
end
if( sum(diff(dat.calc_tel_time)<0) && ERROR_CHECK )
    error('DAR telemetry packets have non-monotonicly increasing times!')
end
if( sum(diff(dat.calc_cal_time)<0) && ERROR_CHECK )
    error('DAR calibration packets have non-monotonicly increasing times!')
end

fprintf("%.2f seconds\n", toc(t_preproc));

%% Geolocation using only S/C telem %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_geoloc = tic;
console_message("Geolocating");

% Ellipsoid Processing %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Gate's Lat, Lon, Altitude
% Use the S/C position and attitude, project the beam's radial on the ellipsoid
% Find beams radial using S/C attitude and beam's attutude
% Using the S/C ECEF position, and beam radial direction, for each range 
% gate, calculate the gate's location in ECEF. gate_pos should be [3 x Ngate].
% Using WGS84 ellipsoid, calculate lat, lon, alt for each range gate.
defs.ellipsoid_name = 'wgs84';

% Check: Do spacecraft data and DAR data match approximately in time?
if min(dat.calc_sci_time) < min(sc.time_j2000_seconds)
    warning("Lower end of science data time exceeds spacecraft time. Will perform extrapolation.");
end
if max(dat.calc_sci_time) > max(sc.time_j2000_seconds)
    warning("Higher end of science data time exceeds spacecraft time. Will perform extrapolation.");
end

%%% Interpolation of telemetry data happens here
position_wrt_ecef_m = interp1(sc.time_j2000_seconds, sc.refs_position_wrt_ecef_m, dat.calc_sci_time, 'linear', 'extrap');
q_body_wrt_ecef     = sc.att_det_q_body_wrt_ecef;
q_dar_wrt_body      = sc.att_det_q_dar_wrt_body;

% Interpolate quaternion with slerp (Spherical Linear Interp)
bin_idxs = discretize(dat.calc_sci_time, sc.time_j2000_seconds);
valid_mask = ~isnan(bin_idxs) & (bin_idxs < length(sc.time_j2000_seconds));
valid_bins = bin_idxs(valid_mask);
t_start = sc.time_j2000_seconds(valid_bins);
t_end   = sc.time_j2000_seconds(valid_bins + 1);
t_weights = (dat.calc_sci_time(valid_mask) - t_start) ./ (t_end - t_start);
Q1_all = q_body_wrt_ecef(valid_bins);
Q2_all = q_body_wrt_ecef(valid_bins + 1);
t_att = slerp(Q1_all, Q2_all, t_weights);

% Slerp extrapolation
if max(dat.calc_sci_time) > max(sc.time_j2000_seconds)
    t_att_idxs = dat.calc_sci_time >= sc.time_j2000_seconds(end);
    t_weights = (dat.calc_sci_time(t_att_idxs) - sc.time_j2000_seconds(end)) / mode(diff(sc.time_j2000_seconds)) + 1;
    t_att(t_att_idxs) = slerp_extrap(q_body_wrt_ecef(end-1), q_body_wrt_ecef(end), t_weights);
end
q_body_wrt_ecef = t_att;

% Calculate look vector
n_look_ecef     = nan*zeros(length(dat.calc_sci_time),3);
prop_dir_local  = [0, 0, 1]; % Propagation direction in SC local CS
for i = 1:length(defs.beam_sel_to_att_ind)  
    beam    = defs.beam_sel_to_att_ind(i);
    m_beam  = dat.sci_beam_select == beam;
    %%% Reference in the spacecraft gets rotated to find look vector
    n_look_ecef(m_beam,:) = rotatepoint(q_body_wrt_ecef(m_beam) .* q_dar_wrt_body .* q_beam_wrt_dar(beam), prop_dir_local);
end

%% Range migration and range gate positions
% This adjusts calc_sci_range_m for the beam-pointing and velocity-dependent range-migration!
% T_us should be a single value given we assume one config per orbit. 
T_us                = interp1( dat.calc_tel_time, double(dat.tel_pulse_width)/40, dat.calc_sci_time,'previous');

if ( isfield(sc, 'refs_velocity_wrt_ecef_mps') ) % This is what we want...
    v_sat_ecef          = interp1(sc.time_j2000_seconds, sc.refs_velocity_wrt_ecef_mps, dat.calc_sci_time, 'linear');
    defs.sc_vel_est_from_position = 0;
else % but for now, if we only have position, estimate velocity
    warning('S/C velocity not found, using position data to estimate velocity!')
    p1                  = interp1(sc.time_j2000_seconds, sc.refs_position_wrt_ecef_m, dat.calc_sci_time-0.05, 'spline');
    p2                  = interp1(sc.time_j2000_seconds, sc.refs_position_wrt_ecef_m, dat.calc_sci_time+0.05, 'spline');
    v_sat_ecef          = (p2-p1)/0.1;
    defs.sc_vel_est_from_position = 1;
end
% Beauchamp, Tanelli & Sy (2021) Observations and Design Considerations for
% Spaceborne Pulse Compression Weather Radar. IEEE TGRS
v_dop                       = sum(v_sat_ecef.*n_look_ecef,2)  + (defs.rcrf_fc_hz - defs.waveform_fc_hz)*lambda/2; 
dr_migration_correction     = v_dop .* (defs.f_Hz.*T_us*1e-6./(defs.bandwidth_mhz*1e6));
m                           = isfinite(dr_migration_correction);
dr_migration_correction(~m) = 0; % deal with nans, inf, etc.

% Calculate the range gate positions taking into account the range migration
calc_sci_range_m        = dat.calc_sci_start_range_m + dr_migration_correction + defs.range_sample_m*[0:(N_gate-1)] + defs.range_offset_m;
calc_sci_start_range_m  = min(calc_sci_range_m,[],2);

%% Range gates are propagated in a Cartesian coordinate system
% Assumes there is a varying range offset depending on the location in the orbit
gates_ecef          = position_wrt_ecef_m + n_look_ecef .* permute(calc_sci_range_m, [1 3 2]); 
gates_ecef          = permute(gates_ecef, [1 3 2]); 
%%% Then convert from ECEF to LLA for L1B output 
tmp_gates           = reshape(gates_ecef, [size(gates_ecef,1)*size(gates_ecef,2) 3]);
gates_lla           = ecef2lla( tmp_gates, defs.ellipsoid_name );
gates_lla           = reshape(gates_lla, [size(gates_ecef,1), size(gates_ecef,2), 3]);
gates_lla           = permute(gates_lla, [3 1 2]); % Reorder dimensions to 3 x Nprof x Nrange
gates_alt_m         = squeeze(gates_lla(3,:,:));
gates_lat_deg       = squeeze(gates_lla(1,:,:));
gates_lon_deg       = squeeze(gates_lla(2,:,:));

%% Find footprint 
range_to_ellipsoid      = ellipsoid_intercept(position_wrt_ecef_m, n_look_ecef, defs.ellipsoid_name);
m                       = find( abs(imag(range_to_ellipsoid))>0 );
range_to_ellipsoid(m)   = nan;

footprint_ECEF      = position_wrt_ecef_m + n_look_ecef .* range_to_ellipsoid;
footprint_lla       = ecef2lla(footprint_ECEF, defs.ellipsoid_name);
footprint_lat       = footprint_lla(:,1);
footprint_lon       = footprint_lla(:,2);

if SHOW_PLOT 
    figure;
    % Only plotting every 1000th sample to reduce lag
    scatter3(gates_lon_deg(1:1000:end), gates_lat_deg(1:1000:end), gates_alt_m(1:1000:end)/1e3, 40, [0 0.4470 0.7410], '.'); 
    xlabel("Latitude (\circ)");
    ylabel("Longitude (\circ)");
    zlabel("Altitude (km)");
    title("Sample Locations (LLA)");
    box off;
    grid on;
end

% Calculate incidence angle
nadir_ECEF          = normalize(footprint_ECEF - lla2ecef([footprint_lat, footprint_lon, 100000*ones(size(footprint_lon))], defs.ellipsoid_name), 2, "norm");
incidence_angle_deg = atan2d( vecnorm(cross(nadir_ECEF, n_look_ecef), 2, 2), dot(nadir_ECEF, n_look_ecef, 2));

%%% Estimate gate that intersects ellipsoid
gate_index_ellipsoid = round((range_to_ellipsoid - calc_sci_start_range_m)/defs.range_sample_m);

fprintf("%.2f seconds\n", toc(t_geoloc));

%% Reflectivity %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_reflec = tic;
console_message("Calculating reflectivity and noise");

%%% Use loopback power to evaluate gain drift
calc_loopback_power     = abs( dat.calc_cal_loopback_real + 1j*dat.calc_cal_loopback_imag ).^2;
cal_loopback_power_db   = 10*log10(mean( calc_loopback_power(:,defs.is_cal_loopback:defs.ie_cal_loopback),2 ));

dca1_temp_c                 = interp1(dat.calc_tel_time, dat.calc_tel_temperature_dca1, dat.calc_cal_time, 'linear','extrap');
calc_cal_loopback_gain_db   = cal_loopback_power_db - defs.reference_loopback_power_db + defs.cal_temp_scale_db*(dca1_temp_c-35);
calc_sci_loopback_gain_db   = interp1(dat.calc_cal_time, calc_cal_loopback_gain_db, dat.calc_sci_time, 'linear','extrap');

%%% Radar constant, Noise Power Estimate, Noise Corrected Reflectivity
% approximate power estimator stdev
if( N_sci_ave<10 )
    p_db_std = 3;
else
    p_db_std = 10*log10(1+1./sqrt(N_sci_ave));
end

% Setup variables for processing
rc_at_start_range_db    = nan*zeros(N_profile,1);     % Radar constant for the starting range
pr_noise_corrected_db   = nan*zeros(N_profile,N_gate);
zm_dbz                  = nan*zeros(N_profile,N_gate);
calc_echo_noise_db      = nan*zeros(N_profile,1);
beam_list               = defs.beam_sel_to_att_ind;
% Process each beam seperately
for i=1:length(beam_list)
    % Select the profiles for the specific beam
    beam    = beam_list(i);
    m_beam  = dat.sci_beam_select == beam;
            
    %%% Calc the radar constant for the beam
    rc_at_start_range_db(m_beam) = defs.radar_const_db(beam) + calc_sci_loopback_gain_db(m_beam) ... 
                    - 20*log10(defs.radar_const_ref_rng_m./calc_sci_start_range_m(m_beam));
    
    %%% Subselect the beam of interest for noise power estimation
    beam_power_db = dat.calc_sci_echo_db(m_beam,:);

    % Calculate noise over a narrow along-track length using all the range gates
    tmp_noise_db    = nan*zeros(size(beam_power_db,1),1);
    for j=1:size(beam_power_db,1)
        is = max(1,j-6);
        ie = min(size(beam_power_db,1),j+6);
        tmp         = reshape(beam_power_db(is:ie,:),1,[]);
        % Step 1: A coarse histogram to find the rough noise power
        [h,edges]   = histcounts(tmp(:));
        centers     = edges(1:end-1)+diff(edges)/2;
        % Step 2: fine histogram search for noise peak
        [~,ix]      = max(h);
        [h,edges]   = histcounts(tmp(:), centers(ix) + [-5:0.05:5]);
        centers     = edges(1:end-1)+diff(edges)/2;
        [val,ix]            = max(h);
        
        % Calculate the noise power centroid from the histogram
        m = find(h>val/3); % count greater than 33% if the peak count
        m = min(m):max(m);
        tmp_noise_db(j)     = sum( h(m).*centers(m) )./ sum(h(m));
    end

    % Now repeat the noise power search with a longer along-track filter
    % using the per profile noise estimates (instead of using the gate
    % power values).  The AT length is "user defined" with
    % defs.noise_window_at_samples.
    tmp_noise_est_db = tmp_noise_db;
    tmp_noise_db    = nan*zeros(size(beam_power_db,1),1);
    for j=1:size(beam_power_db,1)
        is = max(1,j-defs.noise_window_at_samples);
        ie = min(size(beam_power_db,1),j+defs.noise_window_at_samples);
        tmp = tmp_noise_est_db(is:ie);
        % Step 1: A coarse histogram to find the rough noise power
        [h,edges]   = histcounts(tmp(:));
        centers     = edges(1:end-1)+diff(edges)/2;
        % Step 2: fine histogram search for noise peak
        [~,ix]      = max(h);
        [h,edges]   = histcounts(tmp(:), centers(ix) + [-1:0.025:1]);
        centers     = edges(1:end-1)+diff(edges)/2;
        [val,ix]            = max(h);
        % Calculate the noise power centroid from the histogram
        m = find(h>val/3);
        m = min(m):max(m);
        tmp_noise_db(j)     = sum( h(m).*centers(m) )./ sum(h(m));
    end

    % Save the noise power estimates
    calc_echo_noise_db(m_beam)  = tmp_noise_db; % map the noise estimates back to the full data sample
        
    %%% Noise correction and reflectivity estimation
    % Calculated the noise corrected echo power
    tmp                 = 10.^(dat.calc_sci_echo_db(m_beam,:)./10) - 10.^(tmp_noise_db./10);
    tmp(tmp<0)          = nan;
    beam_power_db       = 10*log10(tmp);
    
    % Save the noise corrected power and the calculated reflectivity factor
    pr_noise_corrected_db(m_beam,:) = beam_power_db;
    zm_dbz(m_beam,:)                = beam_power_db + rc_at_start_range_db(m_beam) ...
                                        - 20*log10(calc_sci_start_range_m(m_beam)./calc_sci_range_m(m_beam,:));
end

if SHOW_PLOT 
    sum(isnan(pr_noise_corrected_db(:)))./numel(pr_noise_corrected_db);
    figure
    subplot(2,1,1)
    histogram( dat.calc_sci_echo_db.' )
    subplot(2,1,2)
    histogram( pr_noise_corrected_db.' )

    figure
    clf
    subplot(3,1,1)
    pcolor(dat.calc_sci_echo_db.')
    shading flat
    colorbar
    subplot(3,1,2)
    pcolor(pr_noise_corrected_db.')
    shading flat
    colorbar
    subplot(3,1,3)
    pcolor(zm_dbz.')
    shading flat
    colorbar
end

fprintf("%.2f seconds\n", toc(t_reflec));

%% Sigma0 estimates %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_sigma0 = tic;
console_message("Calculating sigma0");

noise_equiv_dbz = calc_echo_noise_db + rc_at_start_range_db - 20*log10(calc_sci_start_range_m./range_to_ellipsoid);
mainlobe_power_from_peak_db = 20;
min_snr_db                  = 10;

[uncorrected_sigma0_db, ~, point_diag_rng_mean_m, point_diag_rng_width_m, mask_surface_at_edge, num_gates_valid] = ...
    radar_surface_response(defs, zm_dbz, calc_sci_range_m, noise_equiv_dbz, mainlobe_power_from_peak_db, min_snr_db);

m = mask_surface_at_edge | num_gates_valid==0;
uncorrected_sigma0_db(m) = nan;
point_diag_rng_mean_m(m) = nan;
point_diag_rng_width_m(m) = nan;

fprintf("%.2f seconds\n", toc(t_sigma0));

%% Echo Mask %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_echomask = tic;
console_message("Calculating echo mask");

snr_db      = nan*zeros(N_profile,N_gate);
echo_mask   = ones(size(snr_db));

% Echo Mask parameters 
defs.noise_filter_size_voxels       = [5,3]; % Spatial filter size (AT x RNG)
H                                   = ones(defs.noise_filter_size_voxels); % Spatial filter (AT x RNG)
defs.snr_thres_lo_db                = 10*log10(1+2./sqrt(N_sci_ave))+1.5;
defs.snr_thres_hi_db                = 15;
defs.noise_structure_mask_fraction  = 0.67; % The fraction of finite (not nan) values in the region of support (from H) of the noise corrected data required to select the voxel as "echo"

beam_list = defs.beam_sel_to_att_ind;
for i=1:length(beam_list)
    beam                = beam_list(i);
    m_beam              = dat.sci_beam_select == beam;
   
    % NO ECHO
    snr_db(m_beam,:)        = pr_noise_corrected_db(m_beam,:) - repmat(calc_echo_noise_db(m_beam),1,N_gate);
    snr_check               = snr_db(m_beam,:) >= 10*log10(1./sqrt(N_sci_ave));
    m                       = filter2(H,snr_check,'same');
    tmp                     = m<=(sum(H(:))*defs.noise_structure_mask_fraction) & snr_db(m_beam,:)<defs.snr_thres_lo_db; % Tune the parameters
    echo_mask(m_beam,:)     = snr_check & ~tmp;

    % LO SNR and echo structure
    m                       = snr_db(m_beam,:)<defs.snr_thres_lo_db & echo_mask(m_beam,:)>=1;
    tmp                     = echo_mask(m_beam,:);
    tmp(m)                  = 1;
    echo_mask(m_beam,:)     = tmp;
    % MED SNR and echo structure
    m                       = snr_db(m_beam,:)>=defs.snr_thres_lo_db & snr_db(m_beam,:)<defs.snr_thres_hi_db & echo_mask(m_beam,:)>=1;
    tmp                     = echo_mask(m_beam,:);
    tmp(m)                  = 2;
    echo_mask(m_beam,:)     = tmp;
    % HI SNR (echo structure is not considered because of the high SNR)
    m                       = snr_db(m_beam,:)>=defs.snr_thres_hi_db;
    tmp                     = echo_mask(m_beam,:);
    tmp(m)                  = 3;
    echo_mask(m_beam,:)     = tmp;
end

% sum(echo_mask(:)==0) % no echo, low snr, or no structure
% sum(echo_mask(:)==1) % low snr: -1  noise STDEV <= SNR < 2 * noise STDEV
%                        + 1.5 dB AND echo structure detected (for N=15 
%                        pulses averaged, this is estimated as 
%                        -5.88 to +3.31 dB SNR)
% sum(echo_mask(:)==2) % med snr: 2 * noise STDEV <= SNR < 15 dB AND echo 
%                        structure detected.  For N=15, +3.31 dB to 15 dB
%                        SNR.
% sum(echo_mask(:)==3) $ high snr: >= 15 dB SNR.

if SHOW_PLOT 
    snr_thres_min_detect_db         = 10*log10(1./sqrt(N_sci_ave));
    
    figure
    clf
    subplot(4,1,1)
    pcolor(snr_db.')
    shading flat
    colorbar
    subplot(4,1,2)
    tmp = snr_db;
    tmp(tmp<snr_thres_min_detect_db)=nan;
    pcolor(tmp.')
    shading flat
    colorbar
    subplot(4,1,3)
    tmp = snr_db;
    tmp(~logical(echo_mask))=nan;
    pcolor(tmp.')
    shading flat
    colorbar
    subplot(4,1,4)
    tmp = echo_mask;
    pcolor(tmp.')
    shading flat
    colorbar
    colormap(gca,jet(4));
    for i=1:4
        subplot(4,1,i)
        ylim([125 200])
        if(i<=3)
            clim([-10 60])
        elseif(i==4)
            colormap(gca,jet(4));
        end
    end
end

fprintf("%.2f seconds\n", toc(t_echomask));

%% Land/Sea Flag %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_landsea = tic;
console_message("Calculating land/sea flag");

if( ~exist('coast_data','var'))
    coast_data  = load('coastlines.mat');
end
is_ocean_flag    = land_or_ocean(footprint_lat, footprint_lon, coast_data);

fprintf("%.2f seconds\n", toc(t_landsea));

%% 1 km DEM at equator %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_dem = tic;
console_message("Loading and calculating DEM");

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
        defs.dem_name   = [char(dem_name),' -- ',char(dem_path)];
        tmp             = load(dem_path); % DEM in meters now in B_cat
        topo30_dem      = [tmp.B_cat tmp.B_cat(:,1)];
        topo30_lat      = tmp.lat_plot;
        topo30_lon      = [tmp.lon_plot tmp.lon_plot(1)+360];
    end
    DEM_FOUND = 1;
catch
    warning('No DEM found!')
    defs.dem_name   = ['No DEM found. -- ',char(dem_path)];
    DEM_FOUND       = 0;
end

if( DEM_FOUND )
    lon_tmp = mod(footprint_lon,360);
    if( min(topo30_lon)<0 ) % assume +/- 180 deg
        lon_tmp(lon_tmp>180) = lon_tmp(lon_tmp>180) - 360;
    end    
    dem_height_at_ellipsoid_m = interp2(topo30_lon,topo30_lat,topo30_dem,lon_tmp,footprint_lat,'linear');
    dem_height_at_ellipsoid_m(is_ocean_flag) = 0; 
else
    dem_height_at_ellipsoid_m = nan*ones(size(footprint_lat));
end

fprintf("%.2f seconds\n", toc(t_dem));

%% Output data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

t_outstruc = tic;
console_message("Preparing output");

% Output data for L1B from INCUS_Data_dictionary_231213.xlsx
out_dat = []; % Clean the structure

%%% Science Data Fields                                                    Symbol       Units   Dimensions

% Measured Equivalent Reflectivity Factor	                               ZKaMeas	    dBZ	    Nrng x Nprof

% Echo Mask	                                                               EchoMask	    #	    Nrng x Nprof
% Noise Floor	                                                           Pnoise	    dBm	    1 x Nprof
% First Clutter Free Gate	                                               iClutter	    #	    1 x Nprof
% Fractional Surface Gate	                                               fSurf	    F	    1 x Nprof
% Radar Constant	                                                       RadarC0	    dB	    1 x Nprof
out_dat.z_ka_meas_dbz       = zm_dbz.';
out_dat.echo_mask           = echo_mask.';
out_dat.noise_power_db      = calc_echo_noise_db.';
out_dat.beam_index          = dat.sci_beam_select.';

%%% Telemetry and Status Fields                                            Symbol       Units   Dimensions
% Flat Surface Clutter	                                                   ZKaCluttEst	dBZ	    Nrng2 x Nprof
% Gate intersecting surface	                                               iSurf	    #	    1 x Nprof
% Surface Clutter Index		                                                            #	    1 x Nprof
% LandSeaFlag		                                                                    #	    1 x Nprof
% Measured surface NRCS	                                                   S0KaMeas	    dB	    1 x Nprof
% Echo power weighted range centroid                                       rng_mean     m       1 x Nprof
% Echo power weighted range width                                          rng_width    m       1 x Nprof

out_dat.is_ocean_flag           = double(is_ocean_flag).';                  % NetCDF doesn't like logicals
out_dat.sig0_ka_meas_db         = uncorrected_sigma0_db.' - 3.15;           % subtract 3.15dB to approximate peak power instead of integrated power - derived from simulation comparison
out_dat.geodetic_inc_angle_deg  = incidence_angle_deg.';
out_dat.point_diag_rng_mean_m   = point_diag_rng_mean_m.';
out_dat.point_diag_rng_width_m  = point_diag_rng_width_m.';
out_dat.radar_const_at_gate0_db = rc_at_start_range_db.';

%%% Geolocation                                                            Symbol       Units   Dimensions
% 	                                                                       ProfileTime	s	    1 x Nprof
% 	                                                                       UTCstart	    s	    1
% 	                                                                       TAIstart	    s	    1
% Latitude Footprint	                                                   LatF	        deg	    1 x Nprof
% Longitude Footprint	                                                   LonF	        deg	    1 x Nprof
% Range to Intercept	                                                   RangeToInter	km	    1 x Nprof
% Gate intersecting Ellipsoid	                                           iEllipsoid	#	    1 x Nprof
% DEM elevation	                                                           DEMelevation	m	    1 x Nprof
% Geoid Anomaly	                                                           geoidAnomaly	m	    1 x Nprof
% Range of 1st gate	                                                       RangeZero	km	    1 x Nprof
% ProfHeader RangeGate	                                                   dR	        m	    1
% Look Vector	                                                           LookVector	#	    3 x Nprof
% Latitude of Profile trusting ADCS                                        LatP         deg     Nalt x Nat x Nxt
% Longitude of Profile trusting ADCS                                       LonP         deg     Nalt x Nat x Nxt
% Altitude of profile bins                                                 AltP         m       Nalt x Nat x Nxt
% Latitude Profile corrected by topographic features                       LatPcT       deg     Nalt x Nat x Nxt
% Longitude Profile corrected by topographic features                      LonPcT       deg     Nalt x Nat x Nxt
% Altitude Profile corrected by topographic features                       AltPcT       m       Nalt x Nat x Nxt
% out_dat.ProfileTime                 = time.t_rel.';
out_dat.j2000_time_sec              = dat.calc_sci_time.';                               
out_dat.ellipsoid_lat_deg           = footprint_lat.';
out_dat.ellipsoid_lon_deg           = footprint_lon.';
out_dat.ellipsoid_range_m           = range_to_ellipsoid.';
out_dat.ellipsoid_gate_index        = gate_index_ellipsoid.';              % Estimate of gate intersecting ellipsoid, included range migration effect.
out_dat.dem_height_at_ellipsoid_m   = dem_height_at_ellipsoid_m.';         % DEM height at ellipsoid intercept (LatF and LonF)
out_dat.range_gate0_m               = calc_sci_start_range_m.';
out_dat.gates_lat_deg               = gates_lat_deg.';                     
out_dat.gates_lon_deg               = gates_lon_deg.';                     
out_dat.gates_alt_m                 = gates_alt_m.';                  

%%% Required Root Attributes (per CF1.11 & INCUS Metadata Standards)
out_dat.atts.Format                         = "NetCDF-4";
out_dat.atts.IdentifierProductDOIAuthority  = "http://dx.doi.org/";
out_dat.atts.IdentifierProductDOI           = "<placeholder>";
out_dat.atts.Conventions                    = "CF-1.11";
out_dat.atts.source                         = "Dynamic Atmospheric Radar";
out_dat.atts.institution                    = "Colorado State University, Cooperative Institute for Research in the Atmosphere";
out_dat.atts.ProjectAbstract                = "INCUS provides the first tropics-wide investigation of the evolution of the vertical transport of air and water by convective storms (convective mass flux), to understand why, when and where tropical convective storms form, and why only some storms produce severe weather.";
out_dat.atts.DataSetLanguage                = "LanguageCode=ISO 639, default=English";
out_dat.atts.PlatformLongName               = sprintf("INCUS-%d", mod(DAR_SYSTEM_ID,10));
out_dat.atts.PlatformShortName              = sprintf("INCUS-%d", mod(DAR_SYSTEM_ID,10));
out_dat.atts.InstrumentShortName            = "DAR";
out_dat.atts.SensorShortName                = "DAR";
out_dat.atts.ObservationArea                = "Single orbit";
out_dat.atts.StartDirection                 = "A";
out_dat.atts.EndDirection                   = "A";
out_dat.atts.FOVResolution                  = "TBD";
out_dat.atts.ShortName                      = sprintf("INCUS_1B_ZM%d", mod(DAR_SYSTEM_ID,10));
out_dat.atts.LongName                       = "INCUS DAR Equivalent radar reflectivity factor (Ze) [dBZ] and surface normalized radar cross section [dB]";
out_dat.atts.VersionID                      = "TBD <Generated during production>";
out_dat.atts.EntryID                        = sprintf("%s_%s", out_dat.atts.ShortName, out_dat.atts.VersionID); 
out_dat.atts.ProcessingLevel                = "Level 1B";
out_dat.atts.title                          = out_dat.atts.LongName;

%%%Variable Attributes for {'long_name','units'}
out_dat.var_atts = [];
out_dat.var_atts.j2000_time_sec             = {'Profile Time (J2000)','second'};
out_dat.var_atts.gates_lat_deg              = {'Latitude of Range Gates (Profile) trusting ADCS','degrees'};
out_dat.var_atts.gates_lon_deg              = {'Longitude of Range Gates (Profile) trusting ADCS','degrees'};
out_dat.var_atts.gates_alt_m                = {'Altitude of Range Gates (Profile) trusting ADCS','meter'};
out_dat.var_atts.ellipsoid_lat_deg          = {'Ellipsoid Intercept Latitude','degrees_north'};
out_dat.var_atts.ellipsoid_lon_deg          = {'Ellipsoid Intercept Longitude','degrees_east'};
out_dat.var_atts.ellipsoid_range_m          = {'Range to Ellipsoid Intercept','meter'};
out_dat.var_atts.ellipsoid_gate_index       = {'Gate Index of Ellipsoid Intercept (Estimated)','count'};
out_dat.var_atts.dem_height_at_ellipsoid_m  = {'DEM Elevation','meter'};
out_dat.var_atts.range_gate0_m              = {'Range of First Gate','meter'};
out_dat.var_atts.z_ka_meas_dbz              = {'Measured Equivalent Reflectivity Factor','dBZ'};
out_dat.var_atts.noise_power_db             = {'Noise Floor','dB'};
out_dat.var_atts.echo_mask                  = {'Echo Mask','count'};
out_dat.var_atts.beam_index                 = {'Beam Index','count'};
out_dat.var_atts.is_ocean_flag              = {'Land/Sea Flag','count'};
out_dat.var_atts.sig0_ka_meas_db            = {'Measured surface NRCS','dB'};
out_dat.var_atts.radar_const_at_gate0_db    = {'Radar Constant at Gate 0','dB'};
out_dat.var_atts.geodetic_inc_angle_deg     = {'Geodetic Incidence Angle','degrees'};
out_dat.var_atts.point_diag_rng_mean_m      = {'Range Centroid','meter'};
out_dat.var_atts.point_diag_rng_width_m     = {'Range Width','meter'};

%%% Attributes
out_dat.atts.dar_l1a_nc_path        = dar_l1a_nc_path;
out_dat.atts.sc_l1a_path            = sc_l1a_path;
out_dat.atts.l1a_sw_version         = ncreadatt( dar_l1a_nc_path,'/','L1A_sw_version');
out_dat.atts.l1a_packet_def_version = ncreadatt( dar_l1a_nc_path,'/','packet_def_version');
out_dat.atts.version_l1b            = version_l1b;
out_dat.atts.dar_system_id          = DAR_SYSTEM_ID;
out_dat.atts.l1b_error_checking     = ERROR_CHECK;
out_dat.atts.sc_utc_at_start        = char(time.t_start_utc);
out_dat.atts.waveform_crc           = unique( dat.cal_waveform_bram_crc );
out_dat.atts.rcrf_crc               = unique( dat.cal_rcrf_bram_crc );

% store the def configuration info
def_fields = fieldnames(defs);
for i=1:length(def_fields)
    out_dat.atts.(def_fields{i}) = defs.(def_fields{i});
end

fprintf("%.2f seconds\n", toc(t_outstruc));

%% Generate L1B output %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
doubles_var_list    = {'ProfileTime','j2000_time_sec'}; % list of variables names (case-insensitive check) to make doubles instead of singles

t_save_output = tic;
console_message("Saving output L1B data");

% generate NC outputs
if( isempty(dar_l1b_out_path) )
    [root, fname, ext] = fileparts(dar_l1a_nc_path);
    start_time = datetime(time.t_start_j2000, 'ConvertFrom', 'epochtime', 'Epoch', datetime(2000, 1, 1, 12, 0, 0, 'TimeZone', 'UTC'));
    start_time.Format = "uuuuMMdd-HHmmss";
    end_time   = datetime(time.t_end_j2000, 'ConvertFrom', 'epochtime', 'Epoch', datetime(2000, 1, 1, 12, 0, 0, 'TimeZone', 'UTC'));
    end_time.Format = "uuuuMMdd-HHmmss";
    dar_l1b_out_path = fullfile(root, sprintf("./incus_dar%d_%s_%s_1b-zm_v%s.nc", mod(DAR_SYSTEM_ID,10), start_time, end_time, version_l1b));
end

% Write the L1B netcdf
[dar_l1b_out_path] = l1b_netcdf(out_dat, dar_l1b_out_path, doubles_var_list);

fprintf("%.2f seconds\n", toc(t_save_output));
console_message(sprintf("Finished dar_data_l1a_to_l1b. Version: v%s in %.1f mins", version_l1b, toc(t_read_l1a)/60));
fprintf("\n");

end

function t_tic = console_message(t_str)
    t_str = sprintf("[%s] %s", datetime('now','Format','uuuu-MM-dd HH:mm:ss.SSS'), t_str);
    fprintf("%-100s", t_str);
    t_tic = tic;
end