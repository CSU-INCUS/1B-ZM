%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024-2026, by the California Institute of Technology. ALL 
% RIGHTS RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [utc_datetime] = j2000_tai_sec_to_utc_datetime(j2000_tai_seconds)

%j2000_tai_seconds = 9408.5*3600*24;

% Reference epoch (J2000.0 = 2000-Jan-01 12:00:00 UTC)
epoch = datetime(2000, 1, 1, 11, 59, 27.816, 'TimeZone', 'UTC');

% T = leapseconds;
% leap_seconds = seconds( T.CumulativeAdjustment(end) );
leap_seconds = 27; % as of 2025/10/08
warning('assumes 27 leap seconds have accumulated since J2000.')

% Convert to UTC datetime
utc_datetime = epoch + seconds(j2000_tai_seconds + leap_seconds);

