(function () {
    'use strict'

    angular.module('beamng.apps')
        .directive('universalAbsTcsParams', [function () {
            return {
                templateUrl: '/ui/modules/apps/UniversalAbsTcs-param/app.html',
                replace: true,
                restrict: 'EA',
                scope: true,
                link: function (scope) {
                    var defaultTolerance = 100
                    var defaults = {
                        lowSpeedReference: 5,
                        tolerance: 'default',
                        anticipationTime: 0.05,
                        aggressivity: 2.0
                    }

                    function callUniversalAbsTcs (expression, callback) {
                        bngApi.engineLua(
                            '(function() extensions.load("universalAbsTcs"); return universalAbsTcs.' + expression + ' end)()',
                            callback
                        )
                    }

                    function setScopeValues (values) {
                        values = values || defaults
                        scope.lowSpeedReference = Number(values.lowSpeedReference)
                        scope.bCustomTolerance = values.tolerance !== 'default'
                        scope.tolerance = scope.bCustomTolerance ? Number(values.tolerance) : 'default'
                        scope.anticipationTime = Number(values.anticipationTime)
                        scope.aggressivity = Number(values.aggressivity)
                    }

                    function syncCurrentValues () {
                        callUniversalAbsTcs('getParameters()', function (values) {
                            scope.$evalAsync(function () {
                                setScopeValues(values)
                            })
                        })
                    }

                    function getNumber (value, fallback) {
                        var number = Number(value)
                        return isFinite(number) ? number : fallback
                    }

                    function getParametersExpression () {
                        var tolerance = scope.bCustomTolerance
                            ? getNumber(scope.tolerance, defaultTolerance)
                            : 'default'
                        var lowSpeedReferenceMps = getNumber(scope.lowSpeedReference, defaults.lowSpeedReference)
                        return 'setParameters(' +
                            lowSpeedReferenceMps + ',' +
                            JSON.stringify(tolerance) + ',' +
                            getNumber(scope.anticipationTime, defaults.anticipationTime) + ',' +
                            getNumber(scope.aggressivity, defaults.aggressivity) + ')'
                    }

                    scope.toggleCustomTolerance = function () {
                        scope.tolerance = scope.bCustomTolerance ? defaultTolerance : 'default'
                    }

                    scope.apply = function () {
                        callUniversalAbsTcs(getParametersExpression(), function (success) {
                            if (success === false) {
                                syncCurrentValues()
                            }
                        })
                    }

                    scope.reset = function () {
                        setScopeValues(defaults)
                        scope.apply()
                    }

                    scope.$on('VehicleFocusChanged', syncCurrentValues)
                    scope.$on('VehicleReset', syncCurrentValues)

                    setScopeValues(defaults)
                    syncCurrentValues()
                }
            }
        }])
})()