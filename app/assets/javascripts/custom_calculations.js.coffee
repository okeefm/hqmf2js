@hqmf.CustomCalc = {}

@hqmf.CustomCalc.ADE_TTR_OBSERV = (patient, hqmfjs) ->
  inrReadings = DURING(hqmfjs.LaboratoryTestResultInr(patient), hqmfjs.MeasurePeriod(patient));
  inrReadings = new hqmf.CustomCalc.PercentTTREntries(inrReadings)
  [inrReadings.calculatePercentTTR()]

class @hqmf.CustomCalc.PercentTTREntries extends hQuery.CodedEntryList

  constructor: (events) ->
    super()
    @minInr = 2.0
    @maxInr = 3.0
    @minOutOfRange = 0.8
    @maxOutOfRange = 10
    @closestSetpoint = 2.5

    clonedEvents = []
    clonedEvents.push(new event.constructor(event.json)) for event in events

    # remove entries < 0.8
    # reset > 10 to be 10
    # remove duplicate results on entries to those closest to 2.5
    for entry in clonedEvents
      currentClosestValue = null
      for value in entry.values()
        if value.scalar() > @maxOutOfRange
          value.json['scalar'] = '10.0'
        if value.scalar() >= @minOutOfRange && value.scalar() <= @maxOutOfRange
          currentClosestValue = @closestValueToSetpoint(currentClosestValue, value)
      
      passingValues = []
      passingValues = [currentClosestValue.json] if currentClosestValue?
      entry.json['values'] = passingValues

    # filter duplicates to those closest to 2.5 on the same day
    # remove any entries with no values (removed because the value was below 0.8, or no value on source data)
    entriesByDay = {}
    for entry in clonedEvents
      date = entry.timeStamp()
      key = "#{date.getUTCFullYear()}_#{date.getUTCMonth()}_#{date.getUTCDate()}"
      entriesByDay[key] = [] unless entriesByDay[key]
      entriesByDay[key].push(entry) if entry.values().length > 0

    # keep the closest entry to 2.5 when there are multiple entries per day
    finalEvents = []
    for key in _.keys(entriesByDay)
      if (entriesByDay[key].length > 1)
        currentClosestValue = null
        selectedEntry = null
        for entry in entriesByDay[key]
          currentClosestValue = @closestValueToSetpoint(currentClosestValue, entry.values()[0])
          if currentClosestValue.scalar() == entry.values()[0].scalar()
            selectedEntry = entry
        finalEvents.push(selectedEntry)
      else
        finalEvents = finalEvents.concat(entriesByDay[key])

    finalEvents = finalEvents.sort(dateSortAscending)

    @push(event) for event in finalEvents


  closestValueToSetpoint: (one, two) ->
    return two if one == null
    return one if two == null
    if (Math.abs(one.scalar() - @closestSetpoint) > Math.abs(two.scalar() - @closestSetpoint))
      return two
    else
      return one


  calculateDaysInRange: (firstInr, secondInr) ->

    if ((@belowRange(firstInr) and @belowRange(secondInr)) or (@aboveRange(firstInr) and @aboveRange(secondInr)))
      0
    else if (@inRange(firstInr) and @inRange(secondInr))
      @differenceInDays(firstInr,secondInr)
    else if (@outsideRange(firstInr) and @inRange(secondInr))
      @calculateCrossingRange(firstInr,secondInr)
    else if (@inRange(firstInr) and @outsideRange(secondInr))
      @calculateCrossingRange(secondInr, firstInr)
    else 
      @calculateSpanningRange(firstInr, secondInr)

  calculateCrossingRange: (outside,inside) ->
    outsideInr = @inrValue(outside)
    insideInr = @inrValue(inside)
    boundary = @maxInr
    boundary = @minInr if (@belowRange(outside))
    (Math.abs(boundary - insideInr)/Math.abs(insideInr-outsideInr))*@differenceInDays(outside,inside)

  calculateSpanningRange: (first,second) ->
    (1.0/Math.abs(@inrValue(first)-@inrValue(second)))*@differenceInDays(first,second)

  inRange: (entry) ->
    inr = @inrValue(entry)
    inr >= @minInr and inr <= @maxInr

  outsideRange: (entry) ->
    !@inRange(entry)

  belowRange: (entry) ->
    inr = @inrValue(entry)
    inr < @minInr

  aboveRange: (entry) ->
    inr = @inrValue(entry)
    inr > @maxInr
    
  differenceInDays: (first, second) ->
    getIVL(first).low.difference(getIVL(second).low, 'd')
    
  inrValue: (entry) ->
    entry.values()[0].scalar()
    
  totalNumberOfDays: () ->
    @differenceInDays(this[0],this[this.length-1])
    
  calculateTTR: () ->
    total = 0
    for left, i in this
      if (i < this.length-1)
        right = this[i+1]
        total += @calculateDaysInRange(left, right)
    total

  calculatePercentTTR: () ->
    @calculateTTR()/@totalNumberOfDays()*100
    
