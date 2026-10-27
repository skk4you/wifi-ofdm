function [y, calibration] = wifi_rx_frontend(x,c,calibration)
%WIFI_RX_FRONTEND RX analog errors, ADC and separately measured digital trim.
% Calibration is measured once per experiment using a known complex tone
% at the receiver input, bypassing propagation/TX impairments. No test bits.
if nargin < 3
    n = (0:c.calibrationSamples-1).';
    tone = 0.7*exp(2i*pi*137*n/c.calibrationSamples);
    observed = analog(tone,c);
    nv = mean(abs(observed-c.rxDC).^2)*10^(-c.calibrationSNRDB/10);
    observed = observed+sqrt(nv/2)*(randn(size(tone))+1i*randn(size(tone)));
    observed = adc(observed,c);
    fit = [tone conj(tone) ones(size(tone))]\observed;
    calibration = struct('alpha',fit(1),'beta',fit(2),'dc',fit(3), ...
        'imageRejectionDB',20*log10(abs(fit(1))/max(abs(fit(2)),eps)));
end
y = adc(analog(x,c),c);
% To isolate the controls, IQ inversion retains DC unless dcTrim is on.
dc = calibration.dc;
if c.dcTrim, y = bsxfun(@minus,y,dc); end
if c.iqTrim
    if ~c.dcTrim, y = bsxfun(@minus,y,dc); end
    a = calibration.alpha; b = calibration.beta;
    determinant = abs(a)^2-abs(b)^2;
    assert(abs(determinant)>1e-6,'RX IQ matrix is singular.');
    y = (conj(a)*y-b*conj(y))/determinant;
    if ~c.dcTrim, y = bsxfun(@plus,y,dc); end
end
end

function y = analog(x,c)
g = 10^(c.rxIQGainDB/20); p = c.rxIQPhaseDeg*pi/180;
y = real(x)+1i*g*(sin(p)*real(x)+cos(p)*imag(x))+c.rxDC;
end

function y = adc(x,c)
if isinf(c.adcBits), y=x; return; end
step = 2*c.adcFullScale/2^c.adcBits;
quant = @(v) round(min(max(v,-c.adcFullScale),c.adcFullScale-step)/step)*step;
y = quant(real(x))+1i*quant(imag(x));
end
