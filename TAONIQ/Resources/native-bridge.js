/* Native bridge only: computation remains in the versioned model bundle. */
(function () {
    'use strict';
    let generation = 0, chart = null, seed = null, stream = null, horizonMs = null, currentEpochMs = null, dayunPeriods = [];
    function periodsFor(nextChart, horizon) {
        const periods = [], first = nextChart.dayun.firstStartMs;
        if (first > nextChart.birthMs) periods.push({step: 0, pillar: '未起运', startMs: nextChart.birthMs, endMs: first});
        for (let step = 1; ; step++) {
            const start = TaoModel.addYears(first, (step - 1) * 10);
            if (start > horizon) break;
            const period = TaoModel.dayunAt(nextChart, start);
            periods.push({step: period.step, pillar: period.pillar, startMs: period.startMs, endMs: period.endMs});
        }
        return periods;
    }
    function frame(result) {
        const temporal = result.temporal;
        return {
            birthPillars: chart.pillars.slice(),
            flowPillars: temporal.flowPillars.slice(),
            dayun: temporal.dayun.pillar || '未起运',
            dayunPeriods,
            epochMs: temporal.epochMs,
            birthMs: chart.birthMs,
            nowMs: horizonMs,
            seedPointsRemaining: result.seedPointsRemaining === undefined ? 9001 : result.seedPointsRemaining,
            profileLabel: (result.profile || chart.profile).label || (result.profile || chart.profile).id,
            mode: result.points ? 'continuous' : 'frozen-seed'
        };
    }
    function send(id, ok, value, includeNatal) {
        if (ok) nativeResult(JSON.stringify({id, ok, frame: frame(value)}),
            value.points || value.custom, includeNatal ? value.baseline : null);
        else nativeResult(JSON.stringify({id, ok, error: String(value)}), null, null);
    }
    globalThis.TaoNative = {
        invalidate() { generation++; chart = null; seed = null; stream = null; horizonMs = null; currentEpochMs = null; dayunPeriods = []; },
        async request(id, operation, payload) {
            const token = generation;
            const cancelled = () => token !== generation;
            try {
                let result;
                if (operation === 'generate') {
                    const nextChart = TaoModel.chart(payload.input || payload);
                    const nextHorizon = Math.max(nextChart.birthMs, Date.now());
                    const selectedEpoch = payload.epochMs == null ? nextChart.birthMs : payload.epochMs;
                    if (!Number.isSafeInteger(selectedEpoch) || selectedEpoch < nextChart.birthMs || selectedEpoch > nextHorizon)
                        throw Error('观测时刻须位于出生至本次生成时的当前时间之间。');
                    result = await TaoModel.compute({chart: nextChart, epochMs: selectedEpoch}, {shouldCancel: cancelled});
                    if (cancelled()) throw Error('Cancelled');
                    chart = nextChart; seed = result; stream = null;
                    horizonMs = nextHorizon; currentEpochMs = selectedEpoch; dayunPeriods = periodsFor(nextChart, nextHorizon);
                    send(id, true, result, true);
                    return;
                }
                if (!chart || !seed) throw Error('请先生成生辰轨迹。');
                if (operation === 'start') {
                    if (!stream) stream = TaoContinuous.create({sessionId: 'native-' + generation, chart,
                        epochMs: seed.temporal.epochMs, profile: seed.profile, seedPoints: seed.custom,
                        seedParameters: seed.parameters, seedProvenance: seed.temporal.epochMs === chart.birthMs ? 'frozen-birth-window' : 'frozen-date-window'});
                    result = stream.snapshot();
                } else if (operation === 'advance') {
                    if (!stream) throw Error('请先开始连续演化。');
                    if (currentEpochMs + payload.civilMilliseconds > horizonMs) throw Error('演化不能超过本次生成时的当前时间。');
                    result = await stream.advance({civilDurationMs: payload.civilMilliseconds}, {shouldCancel: cancelled});
                } else throw Error('未知的轨迹操作。');
                if (cancelled()) throw Error('Cancelled');
                currentEpochMs = result.epochMs;
                send(id, true, result, false);
            } catch (error) { send(id, false, error.message || error); }
        }
    };
})();
