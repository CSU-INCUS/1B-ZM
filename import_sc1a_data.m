%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024-2026, by the California Institute of Technology. ALL 
% RIGHTS RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [out] = import_sc1a_data(sc_l1a_path)
% Import SC data from S/C L1A netcdf
% version: 0.3 (2026/02/03)
% Specify spacecraft data filename netcdf
% See definition: https://colostate.sharepoint.com/:x:/r/sites/INCUS-Team/_layouts/15/doc2.aspx?sourcedoc=%7BCDFB9CDE-8D1D-48BA-9CFA-C24C5E65BB33%7D&file=1A-SC%20API.xlsx&action=default&mobileredirect=true

% NOTE: (4) is scalar for BCT; (1) is scalar for MATLAB's quaternion class

% Reads in a table
scnci = ncinfo(sc_l1a_path);
scf = {scnci.Variables.Name};
scdat = struct();
for i=1:length(scf)
    scdat.(scf{i}) = ncread(sc_l1a_path, scf{i});
end

% Outputs
% This is for simulation output only
isFoundBodyECEF = any(contains(scf, "Q_BODY_WRT_ECEF"));

% Look for body-to-ECx quaternions
if isFoundBodyECEF
    % This implementation will look for label names and is agnostic to root
    % group variable name changes
    t_labels_b2ecef = sort(scf(contains(scf, "Q_BODY_WRT_ECEF")));
    out.att_det_q_body_wrt_ecef = quaternion(scdat.(t_labels_b2ecef{4}), scdat.(t_labels_b2ecef{1}), scdat.(t_labels_b2ecef{2}), scdat.(t_labels_b2ecef{3}));
else
    t_labels_b2eci = sort(scf(contains(scf, "Q_BODY_WRT_ECI")));
    t_labels_ecef2eci = sort(scf(contains(scf, "Q_ECEF_WRT_ECI")));
    if ~isempty(t_labels_b2eci) & ~isempty(t_labels_ecef2eci)
        att_det_q_body_wrt_eci      = quaternion(scdat.(t_labels_b2eci{4}), scdat.(t_labels_b2eci{1}), scdat.(t_labels_b2eci{2}), scdat.(t_labels_b2eci{3}));
        refs_q_ecef_wrt_eci         = quaternion(scdat.(t_labels_ecef2eci{4}), scdat.(t_labels_ecef2eci{1}), scdat.(t_labels_ecef2eci{2}), scdat.(t_labels_ecef2eci{3}));
        out.att_det_q_body_wrt_ecef = refs_q_ecef_wrt_eci.conj .* att_det_q_body_wrt_eci;
    else
        error("Body-to-ECI/ECEF quaternion information missing!");
    end
end

% Look for body command vectors
isFoundCmdVecBody = any(contains(scf, "PRI_CMD_VEC_BODY") & contains(scf, "SEC_CMD_VEC_BODY"));
if isFoundCmdVecBody
    t_labels_pri = sort(scf(contains(scf, "PRI_CMD_VEC_BODY")));
    t_labels_sec = sort(scf(contains(scf, "SEC_CMD_VEC_BODY")));
    ref_dir_pri   = [scdat.(t_labels_pri{1}), scdat.(t_labels_pri{2}), scdat.(t_labels_pri{3})];
    ref_dir_sec   = [scdat.(t_labels_sec{1}), scdat.(t_labels_sec{2}), scdat.(t_labels_sec{3})];

    % Extract DAR frame from cmd vector
    unique_refs = unique(ref_dir_pri, 'rows'); % => from here, index #2 i.e., [-0.6678 0 0.7443] is the science mode cmd vector -- this is known from Quinn's email
    % Retrieve science mode frame id for retrieving primary and secondary cmd vectors
    sci_id = find(all(ref_dir_pri == unique_refs(2,:), 2), 1);
    % Create DAR frame
    ref_z = ref_dir_pri(sci_id,:);
    ref_y = cross(-ref_dir_sec(sci_id,:), ref_z);
    ref_y = ref_y ./ vecnorm(ref_y,2,2);
    ref_x = cross(ref_y, ref_z);
    ref_x = ref_x ./ vecnorm(ref_x,2,2);
    % This is calculated from BCT
    out.att_det_q_dar_wrt_body = quaternion([ref_x; ref_y; ref_z], "rotmat", "frame");
else
    warning("CMD_VEC_BODY not found. Using default values.");
    out.att_det_q_dar_wrt_body = ones(1, "quaternion");
end

% Look for position vector
isFoundPosition = any(contains(scf, "POSITION_WRT_ECEF"));
if isFoundPosition
    t_labels_pos = sort(scf(contains(scf, "POSITION_WRT_ECEF")));
    out.refs_position_wrt_ecef_m = [scdat.(t_labels_pos{1}), scdat.(t_labels_pos{2}), scdat.(t_labels_pos{3})] * 1e3; % km to m
else
    error("Spacecraft position missing!")
end

% Look for velocity vector
if isFoundPosition
    t_labels_vel = sort(scf(contains(scf, "VELOCITY_WRT_ECEF")));
    out.refs_velocity_wrt_ecef_mps = [scdat.(t_labels_vel{1}), scdat.(t_labels_vel{2}), scdat.(t_labels_vel{3})] * 1e3; % km/s to m/s
else
    warning("Spacecraft velocity missing!")
end

try
    out.datestring_timestamp    = datetime(scdat.ft,"InputFormat","uuuu-MM-dd'T'HH:mm:ss.SSSz","TimeZone","UTC");
catch
    out.datestring_timestamp    = 'not found';
end
out.time_j2000_seconds          = scdat.TIME_J2000_SECONDS;
try
    out.valid                   = strcmpi(scdat.TIME_TIME_VALID,'yes') & strcmpi(scdat.REFS_REFS_VALID,'yes') & strcmpi(scdat.ATT_DET_ATTITUDE_VALID,'yes');
catch
    out.valid                   = 1;
end

% out.refs_latitude_deg           = scdat.REFS_LATITUDE*180/pi;
% out.refs_longitude_deg          = scdat.REFS_LONGITUDE*180/pi;
% out.refs_altitude_m             = scdat.REFS_ALTITUDE*1000;




