function merDB = wifi_evm_to_mer(evmPercent)
%WIFI_EVM_TO_MER Reference-assisted effective received SNR (noise + distortion).
% Uses the SAME residual symbol errors/reference normalization as RMS EVM.
% This is MER, not an independent thermal-noise or DUT firmware SNR estimate.
% NaN stays NaN; zero residual error gives Inf (no artificial SNR ceiling).
validateattributes(evmPercent,{'numeric'},{'real'});
assert(all(isnan(evmPercent(:)) | evmPercent(:)>=0),'EVM percent must be nonnegative or NaN.');
merDB=-20*log10(evmPercent/100);
end
