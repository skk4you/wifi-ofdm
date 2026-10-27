function r = wifi_examples(experiment)
%WIFI_EXAMPLES Ready-to-run experiments; call with one name below.
if nargin<1, experiment='baseline'; end
switch lower(experiment)
    case 'baseline'
        r=wifi_sim;
    case 'trim'
        r=wifi_trim_study(struct('snrDB',10:5:40));
    case 'multipath'
        r=wifi_sim(struct('channel','taps','snrDB',5:5:35));
    case 'mimo'
        r=wifi_sim(struct('channel','tgac','nTx',2,'nRx',2,'nStreams',2, ...
            'standard','11ac','snrDB',10:5:35));
    case 'pa'
        r=wifi_sim(struct('paBackoffDB',3,'snrDB',10:5:40));
    case 'adc'
        r=wifi_sim(struct('adcBits',7,'adcFullScale',2,'snrDB',10:5:40));
    case 'rxper'
        r=wifi_rx_per;
    case 'standards'
        standards={'11a','11n','11ac'}; r=cell(1,3);
        for k=1:3
            r{k}=wifi_sim(struct('standard',standards{k},'mcs',3,'makePlots',false));
        end
        figure('Name','Wi-Fi standards comparison','Color','w');
        for k=1:3
            subplot(1,2,1); hold on; plot(r{k}.settings.snrDB,r{k}.per,'o-');
            subplot(1,2,2); hold on; plot(r{k}.settings.snrDB,r{k}.evmDB,'o-');
        end
        subplot(1,2,1); grid on; xlabel('SNR (dB)'); ylabel('PER'); legend(standards);
        subplot(1,2,2); grid on; xlabel('SNR (dB)'); ylabel('EVM (dB)'); legend(standards);
    otherwise, error('Choose baseline, trim, multipath, mimo, pa, adc, rxper or standards.');
end
end
