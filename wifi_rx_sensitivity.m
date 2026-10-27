function s = wifi_rx_sensitivity(powerDBm,per,threshold)
%WIFI_RX_SENSITIVITY Observed low-power PER crossing; no extrapolation.
validateattributes(powerDBm,{'numeric'},{'vector','real','finite','nonempty'});
validateattributes(per,{'numeric'},{'vector','real','finite','>=',0,'<=',1});
validateattributes(threshold,{'numeric'},{'scalar','real','>',0,'<',1});
x=powerDBm(:); y=per(:);
assert(numel(x)==numel(y) && all(diff(x)>0),'Use matching, increasing power points.');
s=struct('threshold',threshold,'status','no_pass','bracketed',false, ...
    'estimateDBm',NaN,'lowestPassingDBm',NaN,'bracketDBm',[NaN NaN], ...
    'nonmonotonic',any(diff(y)>0),'passWindowsDBm',zeros(0,2));
pass=y<=threshold;
starts=find(diff([false;pass;false])==1);
ends=find(diff([false;pass;false])==-1)-1;
for k=1:numel(starts), s.passWindowsDBm(k,:)=[x(starts(k)) x(ends(k))]; end
i=find(pass,1);
if isempty(i), return; end
s.lowestPassingDBm=x(i);
if i==1
    s.status='below_sweep'; % Passing already at weakest input: crossing unknown.
    return
end
s.status='bracketed'; s.bracketed=true;
s.bracketDBm=[x(i-1) x(i)];
% Linear PER versus dBm interpolation is an estimate, not a measured point
% or statistical confidence bound. Nonmonotonic windows remain visible.
s.estimateDBm=x(i-1)+(threshold-y(i-1))*(x(i)-x(i-1))/(y(i)-y(i-1));
end
