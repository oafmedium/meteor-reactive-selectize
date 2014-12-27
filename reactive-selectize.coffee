# mologie:reactive-selectize
# Copyright 2014 Oliver Kuckertz <oliver.kuckertz@mologie.de>
# See COPYING for license information.

# This class integrates selectize.js controls with Meteor's reactive data
# sources. It specifically implements synchronizing Mongo.Cursor instances,
# but can also handle the results of arbitrary reactive computations.

# Selectize option extensions:
#   options      required, function returning either a Mongo.Cursor or an array
#   optionsMap   optional, works like .map for cursors
#   placeholder  optional, an object like your options but without value
#   selected     optional, an array of values that are selected
#   valueField   optional, defaults to "value"
#   labelField   optional, defaults to "label"

# remotePersist:
# never -> never persist, always delete & deselect options when deleted remotely
# selected -> default, only persist if option is selected
# always -> keep all remotely deleted options

# TODO Option groups
# TODO Reactive placeholder (for localization)
# TODO Reactive default value (for crazy people)

class ReactiveSelectizeController
	constructor: (config) ->
		defaults =
			valueField: "value"
			labelField: "label"
			remotePersist: "selected"
		@_config = _.extend defaults, config
		@_optionsProvider = @_config.options ? []
		@_selectedItems = @_config.selected ? []
	
	attach: ($el) ->
		if @selectize
			return
		@selectize = $el.selectize(@_selectizeOptions())[0].selectize
		@_addPlaceholder() if @_config.placeholder
		@_populateFromDataSource()
	
	stop: ->
		if @_optionsDataSource?
			@_optionsDataSource.stop()
			delete @_optionsDataSource
		@_detach()
	
	getValue: ->
		@selectize.getValue()
	
	getValueArray: ->
		value = @selectize.getValue()
		if not _.isArray value
			value = [value]
		value
	
	isSelected: (option) ->
		@_optionValue(option) in @getValueArray()
	
	_selectizeOptions: ->
		_.omit @_config, 'options', 'optionsMap', 'placeholder', 'selected',
			'remotePersist'
	
	_detach: ->
		@selectize.destroy() if @selectize?
		delete @selectize
	
	_optionValue: (option) ->
		option[@_config.valueField] ? ""
	
	_mapOption: (option) ->
		if typeof @_config.optionsMap is "function"
			option = _.clone option
			@_config.optionsMap option
		else
			option
	
	_makeOption: (id, fields) ->
		option = _.clone fields
		option._id = id
		@_mapOption option
	
	_makeUserOption: (value) ->
		if typeof @_config.create is "function"
			@_config.create value
		else
			option = {}
			option[@_config.valueField] = value
			option[@_config.labelField] = value
			option
	
	_markPersistent: (option) ->
		# FIXME For the persist option to work correctly, options provided by
		# the server must not be marked as "created by user". However,
		# selectize.js's API does not expose such a feature yet and assumes
		# that all options created through addOptions are user options.
		# The following does the job without side effects, but muddles with
		# selectize.js's internal properties and may break at some time.
		delete @selectize.userOptions[@_optionValue option]
	
	_markUserCreated: (option) ->
		# FIXME Like above, this uses a private property.
		@selectize.userOptions[@_optionValue option] = true
	
	_addPlaceholder: ->
		placeholderOption = {}
		placeholderOption[@_config.valueField] = ""
		placeholderOption[@_config.labelField] = ""
		@selectize.addOption placeholderItem
		# TODO use placeholder value
		# TODO update placehodler value reactively if function
	
	_populateFromDataSource: ->
		# Begin listening for changes
		@_optionsDataSource = new DataSourceObserver @_optionsProvider, @_config.valueField,
			batchBegin: => @_beginBatchUpdate()
			batchEnd: => @_endBatchUpdate()
			added: (option) => @_optionAdded option
			changed: (option) => @_optionChanged option
			removed: (option) => @_optionRemoved option
		
		# Get current state
		options = @_optionsDataSource.getSnapshot()
		if @_config.optionsMap
			options = (@_mapOption option for option in options)
		
		# Register options with selectize.js
		for option in options
			@selectize.addOption option
			@_markPersistent option
		
		# Collection option values
		knownValues = _.pluck options, @_config.valueField
		
		# Set values and create user options
		for itemValue in @_selectedItems
			if itemValue in knownValues
				@selectize.addItem itemValue
			else if @_config.create
				option = @_makeUserOption itemValue
				@selectize.addOption option
				@_markUserCreated option
				@selectize.addItem itemValue
		
		# Update control
		@_refreshOptions()
		@_refreshItems()
	
	_refreshOptions: ->
		if @_batchUpdate
			@_batchChangedOptions = true
		else
			@selectize.refreshOptions false
	
	_refreshItems: ->
		if @_batchUpdate
			@_batchChangedItems = true
		else
			@selectize.refreshItems()
	
	_beginBatchUpdate: ->
		@_batchUpdate = true
	
	_endBatchUpdate: ->
		@_batchUpdate = false
		@_refreshOptions() if @_batchChangedOptions
		@_refreshItems() if @_batchChangedItems
		@_batchChangedOptions = false
		@_batchChangedItems = false
	
	_optionAdded: (option) ->
		option = @_mapOption option
		if @_config.create
			# Handle user-created options if needed
			optionValue = @_optionValue option
			selectedValues = @getValueArray()
			if optionValue in selectedValues
				# The option is already there, update it and make it persistent
				@selectize.updateOption optionValue, option
				@_markPersistent option
				return
		@selectize.addOption option
		@_markPersistent option
		@_refreshOptions()
	
	_optionChanged: (option) ->
		option = @_mapOption option
		@selectize.updateOption @_optionValue option, option
	
	_optionRemoved: (option) ->
		option = @_mapOption option
		if @_config.create
			# Apply special behavior according to configuration when
			# user-created options are removed remotely.
			switch @_config.remotePersist
				when "always" then keep = @_config.persist or @isSelected option
				when "selected" then keep = @isSelected option
				else keep = false
			if keep
				@_markUserCreated option
				return
		@selectize.removeOption @_optionValue option		
		@_refreshOptions()
		@_refreshItems()


@ReactiveSelectizeController = ReactiveSelectizeController
