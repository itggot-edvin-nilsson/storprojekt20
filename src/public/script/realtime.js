function httpGet(url, responseCallback) {
	var xhr = new XMLHttpRequest();
	xhr.onreadystatechange = function() {
		if (xhr.readyState === XMLHttpRequest.DONE) {
			responseCallback(xhr.responseText, xhr.status);
		}
	};
	xhr.open('GET', url, true);
	xhr.send();
}

var sensorNames = {};
var sensorUnits;
var sensorReadings;

function distinct(value, index, self) {
	return self.indexOf(value) === index;
}

function generateColor(value) {
	var hash = 23;
	for (var i = 0; i < 4; ++i) {
		hash = hash * 31 + value << i;
	}
	return '#' + (Math.abs(hash) % 16777215).toString(16).padStart(6, '0');
}

function getParameterByName(name, url) {
	if (!url) url = window.location.href;
	name = name.replace(/[\[\]]/g, '\\$&');
	var regex = new RegExp('[?&]' + name + '(=([^&#]*)|&|#|$)'), results = regex.exec(url);
	if (!results) return null;
	if (!results[2]) return '';
	return decodeURIComponent(results[2].replace(/\+/g, ' '));
}

var senasteParam = getParameterByName('senaste');
var freq = 1;
switch (senasteParam) {
case 'timmen':
	freq = 60;
	break;
case 'dygnet':
	freq = 300;
	break;
case 'veckan':
	freq = 1800;
	break;
case 'all':
	freq = 3600;
	break;
}

class ChartController {
	constructor(html, sensors, sensorType) {
		this.sensors = sensors;
		html[1].innerHTML = sensorReadings[sensorType].charAt(0).toUpperCase() + sensorReadings[sensorType].slice(1);
		var htmlChart = html[0].firstElementChild;
		var ctx = htmlChart.getContext('2d');
        var myChart = new Chart(ctx, {
            type: 'line',
            data: {},
            options: {
                scales: {
                    yAxes: [{
                        ticks: {
                            callback: (value, index, values) => value.toLocaleString(),
                            userCallback: (item) => item + ' ' + sensorUnits[sensorType]
                        }
					}],
					xAxes: [{
						ticks: {
							autoSkip: true,
							maxTicksLimit: 40
						}
					}]
				},
				tooltips: {
					callbacks: {
						label: (tooltipItem, data) => tooltipItem.yLabel.toLocaleString() + ' ' + sensorUnits[data.datasets[tooltipItem.datasetIndex].sensorType] + ' (' + sensorReadings[data.datasets[tooltipItem.datasetIndex].sensorType] + ')'
					}
				},
				legend: {
					onClick: function (e, legendItem) {
						var index = legendItem.datasetIndex;
						var sensorId = myChart.data.datasets[index].sensorId;
						var sensorType = myChart.data.datasets[index].sensorType;
						var state = myChart.data.datasets[index].hidden;
						myChart.data.datasets[index].hidden = !state;
						myChart.update();
						if (!state) return;

						this.run = function () {
							httpGet('/realtid/get-sensordata?sensors=' + sensorId, function (response, statusCode) {
								if (statusCode === 200) {
									var data = JSON.parse(response.split('|')[1]);
									myChart.data.datasets[index].data = data[sensorId][sensorType].map(c => c == 0 ? NaN : c);
								}
								myChart.update();
							});
						};
					}
				},
				maintainAspectRatio: false
			}
		});
		this.myChart = myChart;
	}
}

function updateGraph() {
	var sensors = [].concat.apply([], chartControllers.map(c => c.myChart.data.datasets)).filter(c => !c.hidden).map(c => c.sensorId).filter(distinct);
	if (sensors.length === 0) { setTimeout(() => updateGraph(), 1000); return; }
	httpGet('/realtid/get-latest-sensor-value?sensors=' + sensors.join(','), function (response, statusCode) {
		chartControllers.forEach(chartController => {
			chartController.myChart.data.labels.push(new Date().toLocaleString());
			var shift = chartController.myChart.data.labels.length > 60;
			chartController.myChart.data.datasets.forEach(value => {
				if (shift) value.data.shift();
				value.data.push(NaN);
			});

			if (statusCode === 200) {
				response.split(' ').forEach(value => {
					value = value.split(',');
					try {
						var arr = chartController.myChart.data.datasets.find(c => c.sensorId === value[0] && c.sensorType === value[1]).data;
						arr[arr.length - 1] = parseFloat(value[2]);
					} catch (e) { }
				});
			}
			if (shift) chartController.myChart.data.labels.shift();

			chartController.myChart.update({
				duration: 300,
				easing: 'easeInOutSine'
			});
		});
		if (typeof run === 'function') { run(); run = null; }

		if (statusCode === 200 || statusCode === 408)
			updateGraph();
		else
			setTimeout(() => { updateGraph(); }, 1000);
	});
};

var chartControllers = [];

var first = true;

function getChart() {
	var chartContainers = document.getElementsByClassName('chartContainer');

	var htmlContainerChart = chartContainers[chartContainers.length - 1];
	var htmlTitle = htmlContainerChart.previousElementSibling.firstElementChild;

	if (first) {
		first = false;
		return [htmlContainerChart, htmlTitle];
	}

	var titleClone = htmlTitle.parentElement.cloneNode(true);
	var chartClone = htmlContainerChart.cloneNode(true);

	htmlContainerChart.after(chartClone);
	htmlContainerChart.after(titleClone);

	chartContainers = document.getElementsByClassName('chartContainer');
	var titleElement = chartContainers[chartContainers.length - 1].previousElementSibling.firstElementChild;

	var chartElement = chartContainers[chartContainers.length - 1];
	return [chartElement, titleElement];
}

httpGet('/realtid/get-sensor-names-units', function (response, statusCode) {
	if (statusCode !== 200) return;

	var parts = response.split('#');
	parts[0].split('|').forEach(sensor => {
		var subParts = sensor.split(',');
		sensorNames[subParts[0]] = subParts[1];
	});

	sensorUnits = parts[1].split(',');
	sensorReadings = parts[2].split(',');

	var senaste = senasteParam ? '&senaste=' + senasteParam : '';
	httpGet('/realtid/get-sensordata?sensors=' + Object.keys(sensorNames).join(',') + senaste, function (response, statusCode) {
		if (statusCode !== 200) return;
		var parts = response.split('|');
		var startDate = new Date((parts[0] - freq) * 1000);
		var data = JSON.parse(parts[1]);

		var charts = {};

		for (const [sId2, sensors2] of Object.entries(data)) {
			for (const [sType2, sData2] of Object.entries(sensors2)) {
				if (charts[sType2] === undefined) charts[sType2] = [];
				charts[sType2].push(sId2 * 100 + sType2);
			}
		}

		for (const [sensorType, sensors3] of Object.entries(charts)) {
			chartControllers.push(new ChartController(getChart(), sensors3, sensorType));
		}

		chartControllers.forEach(chartController => {
            var numberOfLabels = 0;
			for (const [sId, sensors] of Object.entries(data)) {
				for (const [sType, sData] of Object.entries(sensors)) {
					if (!chartController.sensors.includes(sId * 100 + sType)) continue;
					var color = generateColor(sId + sType * 89);
					chartController.myChart.data.datasets.push({
						label: sensorNames[sId],
						data: sData.map(c => c == 0 ? NaN : c),
						sensorId: sId,
						sensorType: sType,
						fill: false,
						backgroundColor: color,
						borderColor: color + 'aa'
					});
                    if (sData.length > numberOfLabels) numberOfLabels = sData.length;
                }
			}
            var date = new Date(startDate);
			chartController.myChart.data.labels = Array(numberOfLabels).fill().map(() => {
				date.setSeconds(date.getSeconds() + freq); return date.toLocaleString();
			});
			chartController.myChart.update();
		});
	});

	if (freq === 1) this.updateGraph();
});
