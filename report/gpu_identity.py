"""Pure CDP GPU identity selection; raw SystemInfo.gpu must also be retained."""

def identity(raw):
    try:
        if not isinstance(raw,dict):raise ValueError('GPU payload unavailable')
        devices=raw.get('devices')
        if not isinstance(devices,list) or not 1<=len(devices)<=16:raise ValueError('GPU devices unavailable/invalid')
        selected=[]
        for index,device in enumerate(devices):
            if not isinstance(device,dict):raise ValueError('Invalid GPU device')
            row={}
            for key in ('vendorId','deviceId'):
                value=device.get(key)
                if type(value) is not int or value<0:raise ValueError('Missing device identity: '+str(index)+'.'+key)
                row[key]=value
            for key in ('driverVendor','driverVersion'):
                value=device.get(key)
                if not isinstance(value,str) or not value.strip() or len(value)>4096:raise ValueError('Missing driver identity: '+str(index)+'.'+key)
                row[key]=value
            selected.append(row)
        auxiliary=raw.get('auxAttributes',{});renderer={}
        for key in ('glVendor','glRenderer','glVersion'):
            value=auxiliary.get(key)
            if not isinstance(value,str) or not value.strip() or len(value)>4096:raise ValueError('Missing renderer identity: '+key)
            renderer[key]=value
        return {'status':'observed','value':{'devices_in_reported_order':selected,'renderer':renderer}}
    except (ValueError,AttributeError,TypeError) as error:
        return {'status':'unknown','reason':str(error)}
