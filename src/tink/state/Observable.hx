package tink.state;

using tink.CoreApi;

@:forward
abstract Observable<T>(ObservableObject<T>) from ObservableObject<T> to ObservableObject<T> {
  
  public var value(get, never):T;
  
    @:to inline function get_value()
      return this.value;
  
  public inline function new(get, changed)
    this = new BasicObservable<T>(get, changed);
    
  public function combine<A, R>(that:Observable<A>, f:T->A->R) 
    return new Observable<R>(
      function () return f(this.value, that.value), 
      this.changed.join(that.changed)
    );
  
  public function map<R>(f:T->R) 
    return new Observable<R>(
      function () return f(this.value),
      this.changed
    );
  
  public function combineAsync<A, R>(that:Observable<A>, f:T->A->Promise<R>):Observable<Option<Outcome<R, Error>>>
	return combine(that, f).mapAsync(function (x) return x);
  
  public function mapAsync<R>(f:T->Promise<R>):Observable<Option<Outcome<R, Error>>> {
    var ret = new State(None),
	    link:CallbackLink = null;
	bind(function (data) {
		link.dissolve();
		ret.set(None);
		link = f(data).handle(function (r) ret.set(Some(r)));
	});
    return ret;
  } 
    
  public function bind(?options:{ ?direct: Bool }, cb:Callback<T>):CallbackLink
    return 
      switch options {
        case null | { direct: null | false }:
          
          cb.invoke(this.value); 
          this.changed.handle(function () cb.invoke(this.value));
          
        default: 
                      
          var scheduled = false,
              active = true,
              update = function () if (active) {
                cb.invoke(this.value);
                scheduled = false;
              }
          
          function doSchedule() {
            if (scheduled) return;
            
            scheduled = true;
            schedule(update);
          }    
          
          doSchedule();
              
          var link = this.changed.handle(doSchedule);
          
          return function () 
            if (active) {
              active = false;
              link.dissolve();
            }
      }
      
  static var scheduled:Array<Void->Void> = 
    #if (js || tink_runloop) 
      [];
    #else
      null;
    #end
  
  static function schedule(f:Void->Void) 
    switch scheduled {
      case null:
        f();
      case []:
        scheduled.push(f);
        #if tink_runloop
          tink.RunLoop.current.atNextStep(updateAll);
        #elseif js
          js.Browser.window.requestAnimationFrame(function (_) updateAll());
        #else
          throw 'this should be unreachable';
        #end
      case v:
        v.push(f);
    }
  
  static public function updateAll() {
    var old = scheduled;
    scheduled = null;
    
    for (o in old) o();
    
    scheduled = [];
  }
    
  @:from static function ofConstant<T>(value:T):Observable<T> 
    return new Observable(function () return value, new Signal(function (_) return null));
  
}

interface ObservableObject<T> {
  public var changed(get, null):Signal<Noise>;
  public var value(get, never):T;  
}

private class BasicObservable<T> implements ObservableObject<T> {
  
  var getValue:Void->T;
  var valid:Bool;
  var cache:T;
  
  public var changed(get, null):Signal<Noise>;  
  
    inline function get_changed()
      return changed;
      
  public var value(get, never):T;
  
    function get_value() {
      if (!valid) {
        cache = getValue();
        valid = true;
      }
      return cache;
    }
    
  public function new(getValue, changed:Signal<Noise>) {
    this.getValue = getValue;
    this.changed = changed.filter(function (_) return valid && !(valid = false));//the things you do for neat output ...
  }
    
}