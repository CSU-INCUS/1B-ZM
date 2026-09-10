%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Jet Propulsion Laboratory, California Institute of Technology
% Copyright (C) 2024, by the California Institute of Technology. ALL RIGHTS
% RESERVED. United States Government Sponsorship acknowledged. Any 
% commercial use must be negotiated with the Office of Technology Transfer 
% at the California Institute of Technology.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [D] = findLookvectorEllipsoidIntersection(pos, look, ellipsoid_name)

if lower(ellipsoid_name) == "wgs84"
    model = wgs84Ellipsoid;
    A = model.SemimajorAxis;
    B = model.SemimajorAxis;
    C = model.SemiminorAxis;
else
    error("Ellipsoid model not found.");
end

x = pos(:,1);
y = pos(:,2);
z = pos(:,3);

u = look(:,1);
v = look(:,2);
w = look(:,3);

a = (u./A).^2 + (v./B).^2 + (w./C).^2;
b = 2*((x.*u./A.^2) + (y.*v./B.^2) + (z.*w./C.^2));
c = (x./A).^2 + (y./B).^2 + (z./C).^2 - 1;


D = (-b - sqrt(b.^2 - 4*a.*c)) ./ (2*a);
D(~isfinite(D)) = nan;
