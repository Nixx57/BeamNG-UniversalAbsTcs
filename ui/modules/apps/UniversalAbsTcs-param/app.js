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
                        tolerance: 'default'
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
                        scope.tolerance = scope.bCustomTolerance ? Number(values.tolerance) : defaultTolerance
                    }

                    function syncCurrentValues () {
                        callUniversalAbsTcs('getParameters()', function (values) {
                            scope.$evalAsync(function () {
                                setScopeValues(values)
                            })
                        })
                    }

                    function getNonNegativeNumber (value, fallback) {
                        var number = Number(value)
                        return isFinite(number) && number >= 0 ? number : fallback
                    }

                    function getParametersExpression () {
                        var tolerance = scope.bCustomTolerance
                            ? getNonNegativeNumber(scope.tolerance, defaultTolerance)
                            : 'default'
                        var lowSpeedReferenceMps = getNonNegativeNumber(scope.lowSpeedReference, defaults.lowSpeedReference)
                        return 'setParameters(' +
                            lowSpeedReferenceMps + ',' +
                            JSON.stringify(tolerance) + ')'
                    }

                    scope.toggleCustomTolerance = function () {
                        if (!isFinite(Number(scope.tolerance)) || Number(scope.tolerance) < 0) {
                            scope.tolerance = defaultTolerance
                        }
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