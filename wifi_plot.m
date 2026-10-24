function figures = wifi_plot(r)
%WIFI_PLOT Link curves plus a representative packet's RF/OFDM diagnostics.
c=r.settings; x=c.snrDB;
figures(1)=figure('Name','Wi-Fi link metrics','Color','w', ...
    'Position',[60 60 1200 780],'PaperPositionMode','auto');
subplot(2,2,1);
errorbar(x,r.per,r.per-r.perLower,r.perUpper-r.per,'o-');
ylim([0 1]); grid on; xlabel('Input sample SNR (dB)'); ylabel('PER (95% Wilson interval)');
title(sprintf('%s, %d MHz, MCS %d, %dx%d / %d streams', ...
    c.standard,c.bandwidth,c.mcs,c.nTx,c.nRx,c.nStreams));
subplot(2,2,2); plot(x,r.evmDB,'o-',x,-x,'--'); grid on;
xlabel('Input sample SNR (dB)'); ylabel('RMS EVM (dB)');
legend('Reference-based EVM','-SNR guide (not a limit)','Location','best');
subplot(2,2,3); semilogy(x,max(r.berDecoded,1e-8),'o-'); grid on;
xlabel('Input sample SNR (dB)'); ylabel('Decoded-packet BER');
title('Zero BER displayed at 10^{-8}; see exact counts');
subplot(2,2,4); yyaxis left; plot(x,r.goodputMbps,'o-'); ylabel('PHY goodput (Mbps)');
yyaxis right; plot(x,r.effectiveSNRDB,'s-'); ylabel('EVM-derived SNR (dB)'); grid on;
xlabel('Input sample SNR (dB)');
if ~isfield(r.diagnostic,'tx'), return; end
d=r.diagnostic;
figures(2)=figure('Name','Wi-Fi packet diagnostics','Color','w', ...
    'Position',[70 70 1440 850],'PaperPositionMode','auto');
subplot(2,3,1); plot(real(d.equalized(:)),imag(d.equalized(:)),'.'); hold on;
plot(real(d.reference(:)),imag(d.reference(:)),'r+'); axis equal; grid on;
xlabel('I'); ylabel('Q'); title(sprintf('Constellation, SNR %g dB',d.snrDB));
subplot(2,3,2); plot(squeeze(mean(d.perCarrierEVM,3))); grid on;
xlabel('Data carrier index'); ylabel('RMS EVM (%)');
subplot(2,3,3); plot(squeeze(mean(d.perSymbolEVM,3))); grid on;
xlabel('OFDM symbol index'); ylabel('RMS EVM (%)');
subplot(2,3,4); plot(20*log10(max(abs(reshape(d.channelEstimate,size(d.channelEstimate,1),[])),1e-9))); grid on;
xlabel('Occupied carrier index'); ylabel('Estimated channel (dB)');
subplot(2,3,5); [f,p]=spectrum(d.tx(:,1),r.sampleRate); plot(f/1e6,p); hold on;
[f,p]=spectrum(d.rx(:,1),r.sampleRate); plot(f/1e6,p); grid on;
xlabel('Baseband frequency (MHz)'); ylabel('Relative PSD (dB/Hz)'); legend('TX','RX');
subplot(2,3,6);
power=abs(d.tx(:,1)).^2; papr=10*log10(max(power,realmin)/mean(power));
ordered=sort(papr); semilogy(ordered,(numel(ordered):-1:1)/numel(ordered)); grid on;
xlabel('Instantaneous / average power (dB)'); ylabel('CCDF'); title('TX power CCDF (native rate)');
if ~isempty(c.outputDir)
    if ~exist(c.outputDir,'dir'), mkdir(c.outputDir); end
    for k=1:numel(figures)
        saveas(figures(k),fullfile(c.outputDir,sprintf('figure_%d.png',k)));
    end
end
end

function [f,p]=spectrum(x,fs)
n=1024; x=x(:); count=floor(numel(x)/n);
if count==0, x(end+1:n)=0; count=1; end
segments=reshape(x(1:n*count),n,count);
w=0.5-0.5*cos(2*pi*(0:n-1)'/(n-1));
power=mean(abs(fft(bsxfun(@times,segments,w),n)).^2,2)/(fs*sum(w.^2));
p=10*log10(max(fftshift(power),realmin)); f=(-n/2:n/2-1)'*fs/n;
end
